//SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

interface ILiquidityProvider {
    function deposit(uint256 amount) external;

    function makeInitialDeposit(uint256 amount) external;

    function withdraw(uint256 amount) external;

    function withdrawAll() external;
}
