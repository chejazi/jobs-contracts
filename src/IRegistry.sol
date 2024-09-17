// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IRegistry {
    function rewardStakers(address stakedUser, address stakedToken, address rewardToken, uint rewardQuantity) external;
    function autoRegister(address user) external;
    function register(string memory bio) external;
    function update(string memory bio) external;
    function addRegistrar(address registrar) external;
    function removeRegistrar(address registrar) external;
    function isRegistrar(address registrar) external view returns (bool);
    function getRegistrars() external view returns (address[] memory);
    function getRegistrarAt(uint index) external view returns (address);
    function getNumRegistrars() external view returns (uint);
    function getUsers() external view returns (address[] memory);
    function getUserAt(uint index) external view returns (address);
    function getNumUsers() external view returns (uint);
    function isUser(address user) external view returns (bool);
    function getSplitters() external view returns (address[] memory);
    function getSplitterAt(uint index) external view returns (address);
    function getNumSplitters() external view returns (uint);
    function isSplitter(address app) external view returns (bool);
    function getSplitter(address user) external view returns (address);
    function getBio(address user) external view returns (string memory);
}
