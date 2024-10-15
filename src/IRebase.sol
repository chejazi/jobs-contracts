// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IRebase {
    function stake(address token, uint quantity, address app) external;
    function stakeETH(address app) external;
    function unstake(address token, uint quantity, address app) external;
    function unstakeETH(uint quantity, address app) external;
    function restake(address token, uint quantity, address fromApp, address toApp) external;
    function getUserApps(address user) external view returns (address[] memory);
    function getUserAppAt(address user, uint index) external view returns (address);
    function getNumUserApps(address user) external view returns (uint);
    function getAppUsers(address app) external view returns (address[] memory);
    function getAppUserAt(address app, uint index) external view returns (address);
    function getNumAppUsers(address app) external view returns (uint);
    function getAppStake(address app, address token) external view returns (uint);
    function getAppStakes(address app) external view returns (address[] memory, uint[] memory);
    function getAppStakeAt(address app, uint index) external view returns (address, uint);
    function getNumAppStakes(address app) external view returns (uint);
    function getUserAppStake(address user, address app, address token) external view returns (uint);
    function getUserAppStakes(address user, address app) external view returns (address[] memory, uint[] memory);
    function getUserAppStakeAt(address user, address app, uint index) external view returns (address, uint);
    function getNumUserAppStakes(address user, address app) external view returns (uint);
    function getReToken(address token) external view returns (address);
}