// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Snapshot.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

interface Rebased {
    function onStake(address user, address token, uint quantity) external;
    function onUnstake(address user, address token, uint quantity) external;
}

contract Candidate is Rebased, ERC20Snapshot {
    using SafeMath for uint256;

    bool private constant _always = true;
    address private constant _jobsToken = 0xd21111c0e32df451eb61A23478B438e3d71064CB;
    address private constant _rebase = 0x89fA20b30a88811FBB044821FEC130793185c60B;

    address private _directory;
    address private _candidate;
    uint private _lastRewardSnapshotId = 0;
    mapping(address => uint) private _userClaim;
    mapping(uint => address) private _rewardToken;
    mapping(uint => uint) private _rewardQuantity;

    string public bio = "";

    modifier onlyRebase {
        require(msg.sender == _rebase, "Only Rebase");
        _;
    }

    modifier onlyDirectory {
        require(msg.sender == _directory, "Only Directory");
        _;
    }

    constructor(address candidate) ERC20("", "") {
        _candidate = candidate;
    }

    function init(address candidate, string memory text) external {
        require(_candidate == address(0), "Cannot reinitialize");
        _lastRewardSnapshotId = _snapshot();
        _candidate = candidate;
        _directory = msg.sender;
        bio = text;
    }

    function update(string memory text) external {
        require(msg.sender == _candidate);
        bio = text;
    }

    function name() public view override returns (string memory) {
        return string.concat("$JOBS ", Strings.toHexString(_candidate));
    }

    function symbol() public pure override returns (string memory) {
        return "J0x";
    }

    // Disable the transfer function
    function transfer(address, uint256) public pure override returns (bool) {
        if (_always) {
            revert("Transfers disabled");
        }
        return false;
    }

    // Disable the transferFrom function
    function transferFrom(address, address, uint256) public pure override returns (bool) {
        if (_always) {
            revert("Transfers disabled");
        }
        return false;
    }

    function onCommission(address token, uint quantity) external onlyDirectory {
        uint snapshotId = _snapshot();

        _rewardToken[snapshotId] = token;
        _rewardQuantity[snapshotId] = quantity;

        _lastRewardSnapshotId = snapshotId;
    }

    function onStake(address user, address token, uint quantity) external onlyRebase {
        require(token == _jobsToken, "Only $JOBS can be staked");

        if (_userClaim[user] == 0) {
            _userClaim[user] = _getCurrentSnapshotId();
        }

        _mint(user, quantity);
    }

    function onUnstake(address user, address token, uint quantity) external onlyRebase {
        require(token == _jobsToken, "Only $JOBS can be unstaked");

        _burn(user, quantity);
    }

    function getRewards(address user) public view returns (address[] memory, uint[] memory) {
        uint userSnapshotId = _userClaim[user];
        uint lastSnapshotId = _getCurrentSnapshotId();
        uint numRewards = lastSnapshotId - userSnapshotId;

        address[] memory tokens = new address[](numRewards);
        uint[] memory quantities = new uint[](numRewards);

        for (uint i = 0; i < numRewards; i++) {
            uint snapshotId = userSnapshotId + 1 + i;
            tokens[i] = _rewardToken[snapshotId];
            quantities[i] = _rewardQuantity[snapshotId]
                .mul(balanceOfAt(user, snapshotId))
                .div(totalSupplyAt(snapshotId));
        }
        return (tokens, quantities);
    }

    function claim() external {
        (address[] memory tokens, uint[] memory quantities) = getRewards(msg.sender);

        _userClaim[msg.sender] = _getCurrentSnapshotId();

        for (uint i = 0; i < tokens.length; i++) {
            if (quantities[i] > 0) {
                try ERC20(tokens[i]).transfer(msg.sender, quantities[i]) {}
                catch {}
            }
        }
    }
}
