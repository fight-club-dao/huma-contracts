//SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

import "./interfaces/ICredit.sol";
import "./interfaces/IFeeManager.sol";
import "./libraries/BaseStructs.sol";

import "./BaseFeeManager.sol";
import "./BasePool.sol";

import "hardhat/console.sol";

contract BaseCreditPool is ICredit, BasePool {
    // Divider to get monthly interest rate from APR BPS. 10000 * 12
    uint256 public constant BPS_DIVIDER = 120000;
    uint256 public constant HUNDRED_PERCENT_IN_BPS = 10000;

    using SafeERC20 for IERC20;
    using ERC165Checker for address;
    using BaseStructs for BaseCreditPool;

    // mapping from wallet address to the credit record
    mapping(address => BaseStructs.CreditRecord) internal creditRecordMapping;
    // mapping from wallet address to the collateral supplied by this wallet
    mapping(address => BaseStructs.CollateralInfo)
        internal collateralInfoMapping;
    // mapping from wallet address to the last late fee charged date
    mapping(address => uint256) internal lastLateFeeDateMapping;

    constructor(
        address _poolToken,
        address _humaConfig,
        address _poolLockerAddr,
        address _feeManagerAddr,
        string memory _poolName,
        string memory _hdtName,
        string memory _hdtSymbol
    )
        BasePool(
            _poolToken,
            _humaConfig,
            _poolLockerAddr,
            _feeManagerAddr,
            _poolName,
            _hdtName,
            _hdtSymbol
        )
    {}

    /**
     * @notice accepts a credit request from msg.sender
     */
    function requestCredit(
        uint256 _borrowAmt,
        uint256 _paymentIntervalInDays,
        uint256 _numOfPayments
    ) external virtual override {
        // Open access to the borrower
        // Parameter and condition validation happens in initiate()
        initiate(
            msg.sender,
            _borrowAmt,
            address(0),
            0,
            poolAprInBps,
            _paymentIntervalInDays,
            _numOfPayments
        );
    }

    /**
     * @notice the initiation of a loan
     * @param _borrower the address of the borrower
     * @param _borrowAmt the amount of the liquidity asset that the borrower obtains
     * @param _collateralAsset the address of the collateral asset.
     * @param _collateralAmt the amount of the collateral asset
     * todo remove dynamic array, need to coordinate with client for that change.
     */
    function initiate(
        address _borrower,
        uint256 _borrowAmt,
        address _collateralAsset,
        uint256 _collateralAmt,
        uint256 _aprInBps,
        uint256 _paymentIntervalInDays,
        uint256 _remainingPayments
    ) internal virtual {
        protocolAndpoolOn();
        // Borrowers must not have existing loans from this pool
        require(
            creditRecordMapping[msg.sender].state ==
                BaseStructs.CreditState.Deleted,
            "DENY_EXISTING_LOAN"
        );

        // Borrowing amount needs to be higher than min for the pool.
        require(_borrowAmt >= minBorrowAmt, "SMALLER_THAN_LIMIT");

        // Borrowing amount needs to be lower than max for the pool.
        require(maxBorrowAmt >= _borrowAmt, "GREATER_THAN_LIMIT");

        // Populates basic credit info fields
        BaseStructs.CreditRecord memory cr;
        cr.loanAmt = uint96(_borrowAmt);
        cr.remainingPrincipal = uint96(_borrowAmt);
        cr.aprInBps = uint16(_aprInBps);
        cr.paymentIntervalInDays = uint16(_paymentIntervalInDays);
        cr.remainingPayments = uint16(_remainingPayments);
        cr.state = BaseStructs.CreditState.Requested;
        creditRecordMapping[_borrower] = cr;

        // Populates fields related to collateral
        if (_collateralAsset != address(0)) {
            BaseStructs.CollateralInfo memory ci;
            ci.collateralAsset = _collateralAsset;
            ci.collateralAmt = uint88(_collateralAmt);
            collateralInfoMapping[_borrower] = ci;
        }
    }

    /**
     * Approves the loan request with the terms on record.
     */
    function approveCredit(address _borrower) public virtual override {
        protocolAndpoolOn();
        onlyApprovers();
        creditRecordMapping[_borrower].state = BaseStructs.CreditState.Approved;
    }

    function invalidateApprovedCredit(address _borrower)
        public
        virtual
        override
    {
        protocolAndpoolOn();
        onlyApprovers();
        creditRecordMapping[_borrower].deleted = true;
    }

    function isApproved(address _borrower)
        public
        view
        virtual
        override
        returns (bool)
    {
        if (
            (!creditRecordMapping[_borrower].deleted) &&
            (creditRecordMapping[_borrower].state >=
                BaseStructs.CreditState.Approved)
        ) return true;
        else return false;
    }

    function originateCredit(uint256 borrowAmt) external virtual override {
        // Open access to the borrower
        // Condition validation happens in originateCollateralizedCredit()
        return
            originateCollateralizedCredit(
                msg.sender,
                borrowAmt,
                address(0),
                0,
                0
            );
    }

    function originateCollateralizedCredit(
        address _borrower,
        uint256 _borrowAmt,
        address _collateralAsset,
        uint256 _collateralParam,
        uint256 _collateralCount
    ) public virtual override {
        protocolAndpoolOn();

        // msg.sender needs to be the borrower themselvers or the approver.
        if (msg.sender != _borrower) onlyApprovers();

        require(isApproved(_borrower), "CREDIT_NOT_APPROVED");

        // Critical to update cr.loanAmt since _borrowAmt
        // might be lowered than the approved loan amount
        BaseStructs.CreditRecord memory cr = creditRecordMapping[_borrower];
        cr.loanAmt = uint32(_borrowAmt);
        // // Calculates next payment amount and due date
        cr.nextDueDate = uint64(
            block.timestamp +
                uint256(cr.paymentIntervalInDays) *
                SECONDS_IN_A_DAY
        );
        // todo need to call FeeManager for this calculation.
        cr.nextAmtDue = uint32((_borrowAmt * cr.aprInBps) / BPS_DIVIDER);
        creditRecordMapping[_borrower] = cr;

        // Record the collateral info.
        if (_collateralAsset != address(0)) {
            BaseStructs.CollateralInfo memory ci = collateralInfoMapping[
                _borrower
            ];
            if (ci.collateralAsset != address(0)) {
                require(
                    _collateralAsset == ci.collateralAsset,
                    "COLLATERAL_MISMATCH"
                );
            }
            // todo check to make sure the collateral amount meets the requirements
            ci.collateralAmt = uint32(_collateralCount);
            ci.collateralParam = _collateralParam;
            collateralInfoMapping[_borrower] = ci;
        }

        (
            uint256 amtToBorrower,
            uint256 protocolFee,
            uint256 poolIncome
        ) = IFeeManager(feeManagerAddr).distBorrowingAmt(
                _borrowAmt,
                humaConfig
            );

        distributeIncome(poolIncome);

        // //CRITICAL: Asset transfers
        // // Transfers collateral asset
        if (_collateralAsset != address(0)) {
            if (_collateralAsset.supportsInterface(type(IERC721).interfaceId)) {
                IERC721(_collateralAsset).safeTransferFrom(
                    _borrower,
                    poolLockerAddr,
                    _collateralParam
                );
            } else if (
                _collateralAsset.supportsInterface(type(IERC20).interfaceId)
            ) {
                IERC20(_collateralAsset).safeTransferFrom(
                    msg.sender,
                    poolLockerAddr,
                    _collateralCount
                );
            } else {
                revert("COLLATERAL_ASSET_NOT_SUPPORTED");
            }
        }

        // Transfer protocole fee and funds the _borrower
        address treasuryAddress = HumaConfig(humaConfig).humaTreasury();
        PoolLocker locker = PoolLocker(poolLockerAddr);
        locker.transfer(treasuryAddress, protocolFee);
        locker.transfer(_borrower, amtToBorrower);
    }

    /**
     * @notice Borrower makes one payment. If this is the final payment,
     * it automatically triggers the payoff process.
     * @dev "WRONG_ASSET" reverted when asset address does not match
     *
     */
    function makePayment(address _asset, uint256 _amount)
        external
        virtual
        override
    {
        protocolAndpoolOn();

        BaseStructs.CreditRecord memory cr = creditRecordMapping[msg.sender];

        require(_asset == address(poolToken), "WRONG_ASSET");
        require(cr.remainingPayments > 0, "LOAN_PAID_OFF_ALREADY");

        uint256 totalAmt;
        uint256 principal;
        uint256 interest;
        uint256 fees;
        if (cr.remainingPayments == 1) {
            (
                totalAmt,
                principal,
                interest,
                fees, /*unused*/

            ) = getPayoffInfoInterestOnly(msg.sender);
        } else {
            (
                totalAmt,
                principal,
                interest,
                fees, /*unused*/

            ) = getNextPaymentInterestOnly(msg.sender);
        }

        // Do not accept partial payments. Requires _amount to be able to cover
        // the next payment and all the outstanding fees.
        require(_amount >= totalAmt, "AMOUNT_TOO_LOW");

        // Handle overpayment towards principal.
        principal += (_amount - totalAmt);
        totalAmt = _amount;

        if (cr.remainingPayments == 1) {
            cr.nextAmtDue = 0;
            cr.nextDueDate = 0;
            cr.remainingPrincipal = 0;
            cr.feesAccrued = 0;
            cr.remainingPayments = 0;
        } else {
            cr.feesAccrued = 0;
            // Covers the case when the user paid extra amount than required
            // todo needs to address the case when the amount paid can actually pay off
            cr.remainingPrincipal = cr.remainingPrincipal - uint96(principal);
            cr.nextDueDate =
                cr.nextDueDate +
                uint64(cr.paymentIntervalInDays * SECONDS_IN_A_DAY);
            cr.remainingPayments -= 1;
        }

        // Distribute income
        uint256 poolIncome = interest + fees;
        distributeIncome(poolIncome);

        if (cr.remainingPayments == 0) {
            // No way to delete entries in mapping, thus mark the deleted field to true.
            invalidateApprovedCredit(msg.sender);
        }
        creditRecordMapping[msg.sender] = cr;

        // Transfer assets from the _borrower to pool locker
        IERC20 assetIERC20 = IERC20(poolToken);
        assetIERC20.transferFrom(msg.sender, poolLockerAddr, _amount);
    }

    /**
     * @notice Assess and charge penalty fee for early payoff.
     */
    // function assessEarlyPayoffFees(address borrower)
    //     public
    //     virtual
    //     override
    //     returns (uint256 penalty)
    // {
    //     BaseStructs.CreditFeeStructure storage cfs = creditFeesMapping[borrower];
    //     BaseStructs.CreditStatus storage cs = creditRecordMapping[borrower];
    //     if (cfs.back_loading_fee_flat > 0) penalty = cfs.back_loading_fee_flat;
    //     if (cfs.back_loading_fee_bps > 0) {
    //         penalty +=
    //             (cr.remainingPrincipal *
    //                 creditFeesMapping[borrower].back_loading_fee_bps) /
    //             BPS_DIVIDER;
    //     }
    //     cr.feesAccrued += uint32(penalty);
    // }

    /**
     * @notice Borrower requests to payoff the credit
     */
    function payoff(
        address borrower,
        address asset,
        uint256 amount
    ) external virtual override {
        //todo to implement
    }

    // /**
    //  * @notice Checks if a late fee should be charged and charges if needed
    //  * @return fees the amount of fees charged
    //  */
    // function assessLateFee(address borrower)
    //     public
    //     virtual
    //     override
    //     returns (uint256 fees)
    // {
    //     BaseStructs.CreditFeeStructure storage cfs = creditFeesMapping[
    //         borrower
    //     ];
    //     BaseStructs.CreditStatus storage cs = creditRecordMapping[borrower];

    //     // Charge a late fee if 1) passed the due date and 2) there is no late fee charged
    //     // between the due date and the current timestamp.

    //     uint256 newFees;
    //     if (
    //         block.timestamp > cr.nextDueDate &&
    //         cr.lastLateFeeTimestamp < cr.nextDueDate
    //     ) {
    //         if (cfs.late_fee_flat > 0) newFees = cfs.late_fee_flat;
    //         if (cfs.late_fee_bps > 0) {
    //             newFees += (cr.nextAmtDue * cfs.late_fee_bps) / BPS_DIVIDER;
    //         }
    //         cr.feesAccrued += uint32(newFees);
    //         cr.lastLateFeeTimestamp = uint64(block.timestamp);
    //         creditRecordMapping[borrower] = cs;
    //     }
    //     return newFees;
    // }

    /**
     * @notice Triggers the default process
     * @return losses the amount of remaining losses to the pool after collateral
     * liquidation, pool cover, and staking.
     */
    function triggerDefault(address borrower)
        external
        virtual
        override
        returns (uint256 losses)
    {
        protocolAndpoolOn();

        // check to make sure the default grace period has passed.
        require(
            block.timestamp >
                creditRecordMapping[borrower].nextDueDate +
                    poolDefaultGracePeriodInSeconds,
            "DEFAULT_TRIGGERED_TOO_EARLY"
        );

        // FeatureRequest: add pool cover logic

        // FeatureRequest: add staking logic

        // Trigger loss process
        losses = creditRecordMapping[borrower].remainingPrincipal;
        distributeLosses(losses);

        return losses;
    }

    // /**
    //  * @notice Calculates monthly payment for a loan.
    //  * M = P [ i(1 + i)^n ] / [ (1 + i)^n – 1].
    //  * M = Total monthly payment
    //  * P = The total amount of the loan
    //  * I = Interest rate, as a monthly percentage
    //  * N = Number of payments.
    //  */
    // function calcMonthlyPayment()
    //     private
    //     view
    //     returns (uint256 monthlyPayment)
    // {
    //     BaseStructs.BaseStructs.CreditRecord storage ci = loanInfo;
    //     BaseStructs.CreditStatus storage cs = creditRecordMapping[borrower];
    //     uint256 monthlyRateBP = cr.aprInBps / 12;
    //     monthlyPayment = ci
    //         .loanAmt
    //         .mul(monthlyRateBP.mul(monthlyRateBP.add(HUNDRED_PERCENT_IN_BPS)) ^ cr.numOfPayments)
    //         .div(monthlyRateBP.add(HUNDRED_PERCENT_IN_BPS) ^ cr.numOfPayments.sub(HUNDRED_PERCENT_IN_BPS));
    // }

    // /**
    //  * @notice Gets the information of the next payment due
    //  * @return totalAmt the full amount due for the next payment
    //  * @return principal the amount towards principal
    //  * @return interest the amount towards interest
    //  * @return fees the amount towards fees
    //  * @return dueDate the datetime of when the next payment is due
    //  */
    // function getNextPayment(address borrower)
    //     public
    //     virtual
    //     override
    //     returns (
    //         uint256 totalAmt,
    //         uint256 principal,
    //         uint256 interest,
    //         uint256 fees,
    //         uint256 dueDate
    //     )
    // {
    //     fees = assessLateFee(borrower);
    //     BaseStructs.CreditStatus storage cs = creditRecordMapping[borrower];
    //     // For loans w/ fixed payments, the portion towards interest is this month's interest charge,
    //     // which is remaining principal times monthly interest rate. The difference b/w the total amount
    //     // and the interest payment pays down principal.
    //     interest =
    //         (cr.remainingPrincipal * creditFeesMapping[borrower].aprInBps) /
    //         BPS_DIVIDER;
    //     principal = cr.nextAmtDue - interest;
    //     return (
    //         principal + interest + fees,
    //         principal,
    //         interest,
    //         fees,
    //         block.timestamp
    //     );
    // }

    /**
     * @notice Gets the information of the next payment due for interest only
     * @return totalAmt the full amount due for the next payment
     * @return principal the amount towards principal
     * @return interest the amount towards interest
     * @return fees the amount towards fees
     * @return dueDate the datetime of when the next payment is due
     */
    function getNextPaymentInterestOnly(address borrower)
        public
        virtual
        override
        returns (
            uint256 totalAmt,
            uint256 principal,
            uint256 interest,
            uint256 fees,
            uint256 dueDate
        )
    {
        BaseStructs.CreditRecord memory cr = creditRecordMapping[borrower];
        fees = IFeeManager(feeManagerAddr).calcLateFee(
            cr.nextAmtDue,
            cr.nextDueDate,
            lastLateFeeDateMapping[borrower],
            cr.paymentIntervalInDays
        );

        interest = (cr.loanAmt * cr.aprInBps) / BPS_DIVIDER;
        return (interest + fees, 0, interest, fees, block.timestamp);
    }

    // /**
    //  * @notice Gets the payoff information
    //  * @return total the total amount for the payoff
    //  * @return principal the remaining principal amount
    //  * @return interest the interest amount for the last period
    //  * @return fees fees including early payoff penalty
    //  * @return dueDate the date that payment needs to be made for this payoff amount
    //  */
    // function getPayoffInfo(address borrower)
    //     public
    //     virtual
    //     override
    //     returns (
    //         uint256 total,
    //         uint256 principal,
    //         uint256 interest,
    //         uint256 fees,
    //         uint256 dueDate
    //     )
    // {
    //     principal = creditRecordMapping[borrower].remainingPrincipal;
    //     interest =
    //         (principal * creditFeesMapping[borrower].aprInBps) /
    //         BPS_DIVIDER;
    //     fees = assessLateFee(borrower);
    //     fees += (assessEarlyPayoffFees(borrower));
    //     total = principal + interest + fees;
    //     return (total, principal, interest, fees, block.timestamp);
    // }

    /**
     * @notice Gets the payoff information
     * @return total the total amount for the payoff
     * @return principal the remaining principal amount
     * @return interest the interest amount for the last period
     * @return fees fees including early payoff penalty
     * @return dueDate the date that payment needs to be made for this payoff amount
     */
    function getPayoffInfoInterestOnly(address borrower)
        public
        virtual
        override
        returns (
            uint256 total,
            uint256 principal,
            uint256 interest,
            uint256 fees,
            uint256 dueDate
        )
    {
        BaseStructs.CreditRecord memory cr = creditRecordMapping[borrower];
        principal = cr.remainingPrincipal;
        interest = (principal * cr.aprInBps) / BPS_DIVIDER;
        // todo
        fees = IFeeManager(feeManagerAddr).calcLateFee(
            cr.nextAmtDue,
            cr.nextDueDate,
            lastLateFeeDateMapping[borrower],
            cr.paymentIntervalInDays
        );

        // todo need to call with the original principal amount
        fees += IFeeManager(feeManagerAddr).calcBackLoadingFee(principal);
        total = principal + interest + fees;
        return (total, principal, interest, fees, block.timestamp);
    }

    /**
     * @notice Gets high-level information about the loan.
     */
    function getCreditInformation(address borrower)
        external
        view
        returns (
            uint96 loanAmt,
            uint96 nextAmtDue,
            uint64 paymentIntervalInDays,
            uint16 aprInBps,
            uint64 nextDueDate,
            uint96 remainingPrincipal,
            uint16 remainingPayments,
            bool deleted
        )
    {
        BaseStructs.CreditRecord memory cr = creditRecordMapping[borrower];
        return (
            cr.loanAmt,
            cr.nextAmtDue,
            cr.paymentIntervalInDays,
            cr.aprInBps,
            cr.nextDueDate,
            cr.remainingPrincipal,
            cr.remainingPayments,
            cr.deleted
        );
    }

    function getApprovalStatusForBorrower(address borrower)
        external
        view
        returns (bool)
    {
        return
            creditRecordMapping[borrower].state >=
            BaseStructs.CreditState.Approved;
    }

    function onlyApprovers() internal view {
        require(creditApprovers[msg.sender] == true, "APPROVER_REQUIRED");
    }
}
