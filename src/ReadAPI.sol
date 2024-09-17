// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./IJobBoard.sol";
import "./IRegistry.sol";
import "./ISplitter.sol";
import "./IStakeTracker.sol";

contract ReadAPI {
    IJobBoard private constant _jobBoard = IJobBoard(0xc81cb2E24A4373210F62061D929f00b1B9D2E88d);
    IRegistry private constant _registry = IRegistry(0x90427747BF11cf53CADC9c0e1ae7ac62B76b15B9);
    address private constant _jobsToken = 0xd21111c0e32df451eb61A23478B438e3d71064CB; // $JOBS

    function getListing(uint jobId) external view returns (
        string memory title,
        string memory description,
        address manager,
        address token,
        uint quantity,
        uint duration,
        uint createTime,
        uint status
    ) {
        title = _jobBoard.getTitle(jobId);
        description = _jobBoard.getDescription(jobId);
        manager = _jobBoard.getManager(jobId);
        token = _jobBoard.getToken(jobId);
        quantity = _jobBoard.getQuantity(jobId);
        duration = _jobBoard.getDuration(jobId);
        createTime = _jobBoard.getCreateTime(jobId);
        status = _jobBoard.getStatus(jobId);
        return (title, description, manager, token, quantity, duration, createTime, status);
    }
    function getListings(uint[] memory jobIds) external view returns (
        string[] memory titles,
        string[] memory descriptions,
        address[] memory managers,
        address[] memory tokens,
        uint[] memory quantities,
        uint[] memory durations,
        uint[] memory createTimes,
        uint[] memory statuses
    ) {
        titles = new string[](jobIds.length);
        descriptions = new string[](jobIds.length);
        managers = new address[](jobIds.length);
        tokens = new address[](jobIds.length);
        quantities = new uint[](jobIds.length);
        durations = new uint[](jobIds.length);
        createTimes = new uint[](jobIds.length);
        statuses = new uint[](jobIds.length);
        for (uint i = 0; i < jobIds.length; i++) {
            uint jobId = jobIds[i];
            titles[i] = _jobBoard.getTitle(jobId);
            descriptions[i] = _jobBoard.getDescription(jobId);
            managers[i] = _jobBoard.getManager(jobId);
            tokens[i] = _jobBoard.getToken(jobId);
            quantities[i] = _jobBoard.getQuantity(jobId);
            durations[i] = _jobBoard.getDuration(jobId);
            createTimes[i] = _jobBoard.getCreateTime(jobId);
            statuses[i] = _jobBoard.getStatus(jobId);
        }
        return (titles, descriptions, managers, tokens, quantities, durations, createTimes, statuses);
    }

    function getTokenMetadata(address[] memory tokens) public view returns (string[] memory, string[] memory, uint[] memory) {
        string[] memory names = new string[](tokens.length);
        string[] memory symbols = new string[](tokens.length);
        uint[] memory decimals = new uint[](tokens.length);
        for (uint i = 0; i < tokens.length; i++) {
            ERC20 token = ERC20(tokens[i]);
            names[i] = token.name();
            symbols[i] = token.symbol();
            decimals[i] = token.decimals();
        }
        return (names, symbols, decimals);
    }

    function getStakedJobs(address[] memory users) external view returns (uint[] memory) {
        uint[] memory staked = new uint[](users.length);
        for (uint i = 0; i < users.length; i++) {
            address splitter = _registry.getSplitter(users[i]);
            if (splitter != address(0)) {
                address stakeTracker = ISplitter(splitter).getStakeTracker(_jobsToken);
                if (stakeTracker != address(0)) {
                    staked[i] = IERC20(stakeTracker).totalSupply();
                }
            }
        }
        return staked;
    }
}
