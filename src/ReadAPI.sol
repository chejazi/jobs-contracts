// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./IRebase.sol";
import "./IJobBoard.sol";
import "./IRegistry.sol";
import "./ISplitter.sol";
import "./IStakeTracker.sol";

contract ReadAPI {
    IRebase private constant _rebase = IRebase(0x89fA20b30a88811FBB044821FEC130793185c60B);
    IJobBoard private constant _jobBoard = IJobBoard(0x2D2BB82ab894267C5Ba80D26e9B4f7470315Bdd8);
    IRegistry private constant _registry = IRegistry(0x4011AaBAD557be4858E08496Db5B1f506a4e6167);
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

    function getTokenMetadata(address[] memory tokens) public view returns (string[] memory, string[] memory, uint[] memory, uint[] memory supply) {
        string[] memory names = new string[](tokens.length);
        string[] memory symbols = new string[](tokens.length);
        uint[] memory decimals = new uint[](tokens.length);
        uint[] memory supplies = new uint[](tokens.length);
        for (uint i = 0; i < tokens.length; i++) {
            ERC20 token = ERC20(tokens[i]);
            names[i] = token.name();
            symbols[i] = token.symbol();
            decimals[i] = token.decimals();
            supplies[i] = token.totalSupply();
        }
        return (names, symbols, decimals, supplies);
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

    function getScouters(address user) external view returns (address[] memory stakers, uint[] memory amounts) {
        address splitter = _registry.getSplitter(user);
        if (splitter != address(0)) {
            stakers = _rebase.getAppUsers(splitter);
            amounts = new uint[](stakers.length);
            for (uint i = 0; i < stakers.length; i++) {
                amounts[i] = _rebase.getUserAppStake(stakers[i], splitter, _jobsToken);
            }
        }
        return (stakers, amounts);
    }

    function getScouting(address user) external view returns (address[] memory scouting, uint[] memory amounts) {
        address[] memory apps = _rebase.getUserApps(user);
        uint numSplitters = 0;
        for (uint i = 0; i < apps.length; i++) {
            if (_registry.isSplitter(apps[i])) {
                numSplitters++;
            } else {
                apps[i] = address(0);
            }
        }
        scouting = new address[](numSplitters);
        amounts = new uint[](numSplitters);
        uint splitterCounter = 0;
        for (uint i = 0; i < apps.length; i++) {
            if (apps[i] != address(0)) {
                scouting[splitterCounter] = ISplitter(apps[i]).getUser();
                amounts[splitterCounter] = _rebase.getUserAppStake(user, apps[i], _jobsToken);
                splitterCounter++;
            }
        }
        return (scouting, amounts);
    }

    function getScoutEarnings(address scout, address[] memory scouting) external view returns (
        address[] memory users,
        address[] memory splitters,
        uint[] memory snapshotIds,
        address[] memory tokens,
        uint[] memory amounts,
        bool[] memory claimed
    ) {
        ISplitter splitter;
        IStakeTracker stakeTracker;
        uint n = 0;
        for (uint i = 0; i < scouting.length; i++) {
            splitter = ISplitter(_registry.getSplitter(scouting[i]));
            stakeTracker = IStakeTracker(splitter.getStakeTracker(_jobsToken));
            n += stakeTracker.getCurrentSnapshotId();
        }
        users = new address[](n);
        splitters = new address[](n);
        snapshotIds = new uint[](n);
        tokens = new address[](n);
        amounts = new uint[](n);
        claimed = new bool[](n);
        n = 0;
        for (uint i = 0; i < scouting.length; i++) {
            splitter = ISplitter(_registry.getSplitter(scouting[i]));
            stakeTracker = IStakeTracker(splitter.getStakeTracker(_jobsToken));
            address user = splitter.getUser();
            for (uint j = stakeTracker.getCurrentSnapshotId(); j > 0; j--) {
                users[n] = user;
                splitters[n] = address(splitter);
                snapshotIds[n] = j;
                (tokens[n], amounts[n]) = stakeTracker.getUserReward(scout, j);
                claimed[n] = stakeTracker.hasClaimed(scout, j);
                n++;
            }
        }
        return (
            users, splitters, snapshotIds, tokens, amounts, claimed
        );
    }
}
