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
            interestOnly,
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
        bool _interestOnly,
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
        cr.interestOnly = _interestOnly;
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
        // Condition validation happens in originateCreditWithCollateral()
        return
            originateCreditWithCollateral(
                msg.sender,
                borrowAmt,
                address(0),
                0,
                0
            );
    }

    function originateCreditWithCollateral(
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

        uint256 principal;
        uint256 interest;
        uint256 fees;
        bool paidOff;

        (principal, interest, fees, paidOff) = IFeeManager(feeManagerAddr)
            .getNextPayment(cr, lastLateFeeDateMapping[msg.sender], _amount);

        uint256 totalDue = principal + interest + fees;

        // Do not accept partial payments. Requires _amount to be able to cover
        // the next payment and all the outstanding fees.
        // todo figure out a good way to communicate back to the user when
        // the amount is insufficient,
        require(_amount >= totalDue, "AMOUNT_TOO_LOW");

        // Handle overpayment towards principal.
        if (_amount > totalDue) {
            uint256 extra = _amount - totalDue;

            if (extra < (cr.remainingPrincipal - principal)) {
                // The extra does not cover all the remaining principal, simply
                // apply the extra towards principal payment
                principal += extra;
            } else {
                // the extra can cover the remaining principal, check if it is
                // enough to cover back loading fee.
                extra -= cr.remainingPrincipal - principal;
                principal = cr.remainingPrincipal;

                uint256 backloadingFee = IFeeManager(feeManagerAddr)
                    .calcBackLoadingFee(cr.loanAmt);
                if (extra > backloadingFee) {
                    fees += backloadingFee;
                    paidOff = true;
                }
            }
        }

        // // It is tricky if there is backloading fee.

        // uint256 total = principal + interest + fees;

        // // Check if the extra principal payment is enough to pay off
        // if (_paymentAmount >= total && paidOff == false) {
        //     uint256 extraAmount = _paymentAmount - total;
        //
        //     // check if there is enough to cover back loading fee.
        //     if (extraAmount >= backloadingFee) {
        //         fees += backloadingFee;
        //         principal = cr.remainingPrincipal;
        //         paidOff = true;
        //     }
        // }

        if (paidOff) {
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
     * @notice Borrower requests to payoff the credit
     */
    function payoff(
        address borrower,
        address asset,
        uint256 amount
    ) external virtual override {
        //todo to implement
    }

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
