// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "./ISplitter.sol";
import "./IRebased.sol";
import "./StakeTracker.sol";

contract Splitter is ISplitter, Rebased {
    using EnumerableSet for EnumerableSet.AddressSet;

    address private constant _rebase = 0x89fA20b30a88811FBB044821FEC130793185c60B;
    address private immutable _stakeTrackerTemplate;
    address private immutable _directory;
    address private _user;
    mapping(address => address) private _stakeTracker;

    modifier onlyRebase {
        require(msg.sender == _rebase, "Only Rebase");
        _;
    }

    modifier onlyDirectory {
        require(msg.sender == _directory, "Only Directory");
        _;
    }

    constructor(address directory) {
        StakeTracker template = new StakeTracker();
        template.init(address(this), address(0), address(0));

        _stakeTrackerTemplate = address(template);
        _directory = directory;
    }

    function init(address user) external {
        require(_user == address(0), "Cannot reinitialize");
        require(user != address(0), "User cannot be null");
        _user = user;
    }

    function onStake(address user, address token, uint quantity) external onlyRebase {
        address stakeTracker = _getOrCreateStakeTracker(token);
        StakeTracker(stakeTracker).add(user, quantity);
    }

    function onUnstake(address user, address token, uint quantity) external onlyRebase {
        address stakeTracker = _getOrCreateStakeTracker(token);
        StakeTracker(stakeTracker).remove(user, quantity);
    }

    function split(address stakedToken, address rewardToken, uint rewardQuantity) external onlyDirectory {
        address stakeTracker = _getOrCreateStakeTracker(stakedToken);
        StakeTracker(stakeTracker).track(rewardToken, rewardQuantity);
    }

    function claim(address to, address[] memory stakedTokens, uint[][] memory snapshotIds) external {
        for (uint n = 0; n < stakedTokens.length; n++) {
            address stakeTracker = _getOrCreateStakeTracker(stakedTokens[n]);
            (address[] memory rewardTokens, uint[] memory quantities) = StakeTracker(stakeTracker).claim(msg.sender, snapshotIds[n]);

            for (uint i = 0; i < rewardTokens.length; i++) {
                if (quantities[i] > 0) {
                    require(
                        IERC20(rewardTokens[i]).transfer(to, quantities[i]),
                        "Unable to claim tokens"
                    );
                }
            }
        }
    }

    function _getOrCreateStakeTracker(address token) internal returns (address) {
        address stakeTracker = _stakeTracker[token];
        if (stakeTracker == address(0)) {
            address user = _user;
            stakeTracker = Clones.cloneDeterministic(_stakeTrackerTemplate, keccak256(abi.encode([user, token])));
            StakeTracker(stakeTracker).init(address(this), user, token);
            StakeTracker(stakeTracker).add(user, 1);
            _stakeTracker[token] = stakeTracker;
        }
        return stakeTracker;
    }

    function getDirectory() external view returns (address) {
        return _directory;
    }

    function getUser() external view returns (address) {
        return _user;
    }

    function getStakeTracker(address token) external view returns (address) {
        return _stakeTracker[token];
    }
}
