//SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

/**
 * @notice A token that tracks the gains and losses that the token owner can claim.
 * It is inspired by EIP-2222, which hanldes the gains only. The enhancement allows
 * the handling of the principle, gains, and losses.
 */
interface IHDT {
    /**
     * @dev Returns the total amount of funds a given address is able to withdraw currently.
     * @param owner Address of the token holder
     * @return a uint256 representing the available funds for a given account
     */
    function withdrawableFundsOf(address owner) external view returns (uint256);

    function mint(address account, uint256 assets) external returns (uint256 shares);

    function burn(address account, uint256 assets) external returns (uint256 shares);

    function burnShares(address account, uint256 shares) external returns (uint256 assets);
}
