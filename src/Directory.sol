// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./Candidate.sol";

contract Directory is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    address private immutable _clonableToken;

    mapping(address => address) private _userCandidate;
    EnumerableSet.AddressSet private _jobBoards;
    EnumerableSet.AddressSet private _users;
    EnumerableSet.AddressSet private _candidates;

    modifier onlyJobBoard {
        require(isJobBoard(msg.sender), "Not a Job board");
        _;
    }

    constructor() {
        _clonableToken = address(new Candidate(address(this)));
    }

    function _register(address user, string memory bio) internal returns (address) {
        address candidate = _userCandidate[user];
        if (candidate == address(0)) {
            candidate = Clones.cloneDeterministic(_clonableToken, bytes32(uint(uint160(user))));
            Candidate(candidate).init(user, bio);
            _userCandidate[user] = candidate;
            _users.add(user);
            _candidates.add(candidate);
        }
        return candidate;
    }

    function commission(address user, address token, uint quantity) external onlyJobBoard {
        address candidate = _register(user, "");
        require(IERC20(token).transferFrom(msg.sender, candidate, quantity), "Unable to transfer token");
        Candidate(candidate).onCommission(token, quantity);
    }

    function autoRegister(address user) external onlyJobBoard {
        _register(user, "");
    }

    function register(string memory bio) external {
        _register(msg.sender, bio);
    }

    function addJobBoard(address jobBoard) external onlyOwner {
        _jobBoards.add(jobBoard);
    }
    function removeJobBoard(address jobBoard) external onlyOwner {
        _jobBoards.remove(jobBoard);
    }
    function isJobBoard(address jobBoard) public view returns (bool) {
        return _jobBoards.contains(jobBoard);
    }
    function getJobBoards() external view returns (address[] memory) {
        return _jobBoards.values();
    }

    function getCandidate(address user) external view returns (address) {
        return _userCandidate[user];
    }
    function isCandidate(address user) external view returns (bool) {
        return _candidates.contains(user);
    }
    function getCandidates(address[] memory users) external view returns (address[] memory) {
        address[] memory candidates = new address[](users.length);
        for (uint i = 0; i < users.length; i++) {
            candidates[i] = _userCandidate[users[i]];
        }
        return candidates;
    }

    function getCandidate(uint index) external view returns (address) {
        return _candidates.at(index);
    }
    function getCandidates() external view returns (address[] memory) {
        return _candidates.values();
    }
    function getNumCandidates() external view returns (uint) {
        return _candidates.length();
    }

    function getUsers() external view returns (address[] memory) {
        return _users.values();
    }
    function getUserAt(uint index) external view returns (address) {
        return _users.at(index);
    }
    function getNumUsers() external view returns (uint) {
        return _users.length();
    }
}
