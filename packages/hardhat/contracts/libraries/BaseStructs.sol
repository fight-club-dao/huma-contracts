//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "hardhat/console.sol";

library BaseStructs {
    /**
     * @notice CreditRecord stores the overall info and status about a credit originated.
     * @dev amounts are stored in uint96, all counts are stored in uint16
     * @dev each struct can have no more than 13 elements.
     */
    struct CreditRecord {
        // fields related to the overall picture of the loan
        uint96 loanAmt;
        uint96 nextAmtDue;
        uint64 nextDueDate;
        uint96 remainingPrincipal;
        uint96 feesAccrued;
        uint16 paymentIntervalInDays;
        uint16 aprInBps;
        uint16 remainingPayments;
        CreditState state;
        bool deleted;
    }

    /**
     * @notice CollateralInfo stores collateral used for credits.
     * @dev Used uint88 for collateralAmt to pack the entire struct in 2 storage units
     * @dev deleted is used to mark the entry as deleted in mappings
     * @dev collateralParam is used to store info such as NFT tokenId
     */
    struct CollateralInfo {
        address collateralAsset;
        uint88 collateralAmt;
        bool deleted;
        uint256 collateralParam;
    }

    enum CreditState {
        Deleted,
        Requested,
        Approved,
        Originated,
        GoodStanding,
        Delayed,
        PaidOff,
        InDefaultGracePeriod,
        Defaulted
    }

    // Please do NOT delete during development stage.
    // Debugging helper function. Please comment out after finishing debugging.
    function printCreditInfo(CreditRecord storage cr) public view {
        console.log("\n##### Status of the Credit #####");
        console.log("cr.loanAmt=", uint256(cr.loanAmt));
        console.log("cr.nextDueDate=", uint256(cr.nextDueDate));
        console.log("cr.remainingPrincipal=", uint256(cr.remainingPrincipal));
        console.log("cr.feesAccrued=", uint256(cr.feesAccrued));
        console.log(
            "cr.paymentIntervalInDays=",
            uint256(cr.paymentIntervalInDays)
        );
        console.log("cr.apr_in_bps=", uint256(cr.aprInBps));
        console.log("cr.remainingPayments=", uint256(cr.remainingPayments));
        console.log("cr.state=", uint256(cr.state));
        console.log("cr.deleted=", cr.deleted);
    }
}