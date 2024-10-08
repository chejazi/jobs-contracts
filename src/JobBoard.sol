// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import "./IRegistry.sol";

contract JobBoard {
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableMap for EnumerableMap.UintToUintMap;
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    struct Job {
        string title;
        string description;
        address manager;
        address token;
        uint quantity;
        uint duration;
        uint createTime;

        address pendingManager;
        bytes32 pendingOffer;

        address worker;
        uint startTime;
        uint timePaid;
        uint timeRefunded;

        mapping(address => bool) funderRefunded;

        EnumerableMap.AddressToUintMap funderQuantities;
        EnumerableMap.AddressToUintMap applicantTimes;
    }

    struct Profile {
        EnumerableSet.UintSet managed;
        EnumerableSet.UintSet worked;

        EnumerableMap.UintToUintMap fundedTimes;
        EnumerableMap.UintToUintMap appliedTimes;
    }

    struct Project {
        EnumerableSet.UintSet open;
        EnumerableSet.UintSet filled;
        EnumerableSet.UintSet cancelled;
    }

    mapping(uint => Job) private _jobs;
    mapping(address => Profile) private _profiles;
    mapping(address => Project) private _projects;
    EnumerableSet.AddressSet _tokens;

    IRegistry private immutable _registry;

    string private constant ERROR_TRANSFER_FAILED = "Transfer failed";
    string private constant ERROR_NOT_AUTHORIZED = "Not authorized";
    string private constant ERROR_INVALID_JOB_STATE = "Invalid job state";
    string private constant ERROR_INVALID_VALUE = "Invalid value";

    uint public constant JOB_STATUS_CREATED = 1;
    uint public constant JOB_STATUS_WORKING = 2;
    uint public constant JOB_STATUS_ENDED = 3;

    uint public constant FEE_BIPS = 1000; // 10%
    uint public constant WORKER_BIPS = 9000; // 90%
    uint public constant TOTAL_BIPS = 10000; // 100%

    uint public counter;

    address public constant STAKE_TOKEN = 0xd21111c0e32df451eb61A23478B438e3d71064CB; // $JOBS

    modifier isRegistered {
        _registry.autoRegister(msg.sender);
        _;
    }

    constructor(address registry) {
        _registry = IRegistry(registry);
    }

    function create(string memory title, string memory description, address token, uint quantity, uint duration) external isRegistered {
        uint jobId = ++counter;
        Job storage job = _jobs[jobId];

        require(
            quantity > 0 &&
            duration > 0 &&
            duration < 1000000000,
            ERROR_INVALID_VALUE
        );

        job.title = title;
        job.description = description;
        job.manager = msg.sender;
        job.token = token;
        job.duration = duration;
        job.createTime = block.timestamp;

        _profiles[msg.sender].managed.add(jobId);
        _projects[token].open.add(jobId);
        _tokens.add(token);

        fund(jobId, quantity);
    }

    function update(uint jobId, string memory description) external {
        Job storage job = _jobs[jobId];

        require(getStatus(jobId) == JOB_STATUS_CREATED, ERROR_INVALID_JOB_STATE);
        require(job.manager == msg.sender, ERROR_NOT_AUTHORIZED);

        job.description = description;
    }

    function transfer(uint jobId, address manager) external {
        Job storage job = _jobs[jobId];

        require(getStatus(jobId) != JOB_STATUS_ENDED, ERROR_INVALID_JOB_STATE);
        require(job.manager == msg.sender, ERROR_NOT_AUTHORIZED);

        job.pendingManager = manager;
    }

    function manage(uint jobId) external {
        Job storage job = _jobs[jobId];

        require(getStatus(jobId) != JOB_STATUS_ENDED, ERROR_INVALID_JOB_STATE);
        require(job.pendingManager == msg.sender, ERROR_NOT_AUTHORIZED);

        job.manager = msg.sender;
        _profiles[msg.sender].managed.add(jobId);
    }

    function fund(uint jobId, uint quantity) public isRegistered {
        Job storage job = _jobs[jobId];

        require(getStatus(jobId) == JOB_STATUS_CREATED, ERROR_INVALID_JOB_STATE);

        (,uint funderQuantity) = job.funderQuantities.tryGet(msg.sender);

        job.funderQuantities.set(msg.sender, funderQuantity.add(quantity));
        job.quantity = job.quantity.add(quantity);

        _profiles[msg.sender].fundedTimes.set(jobId, block.timestamp);

        require(
            IERC20(job.token).transferFrom(msg.sender, address(this), quantity),
            ERROR_TRANSFER_FAILED
        );
    }

    function apply_(uint jobId) external isRegistered {
        Job storage job = _jobs[jobId];

        require(getStatus(jobId) == JOB_STATUS_CREATED, ERROR_INVALID_JOB_STATE);

        _profiles[msg.sender].appliedTimes.set(jobId, block.timestamp);

        if (!job.applicantTimes.contains(msg.sender)) {
            job.applicantTimes.set(msg.sender, block.timestamp);
        }
    }

    function remove(uint jobId) external {
        _profiles[msg.sender].appliedTimes.remove(jobId);
    }

    function offer(uint jobId, bytes32 hash) public {
        Job storage job = _jobs[jobId];

        require(getStatus(jobId) == JOB_STATUS_CREATED, ERROR_INVALID_JOB_STATE);
        require(job.manager == msg.sender, ERROR_NOT_AUTHORIZED);

        job.pendingOffer = hash;
    }

    function cancel(uint jobId) external {
        Job storage job = _jobs[jobId];

        require(getStatus(jobId) == JOB_STATUS_CREATED, ERROR_INVALID_JOB_STATE);

        job.timeRefunded = job.duration;

        _projects[job.token].open.remove(jobId);
        _projects[job.token].cancelled.add(jobId);

        refund(jobId, msg.sender);
    }

    function accept(uint jobId, string memory secret) external isRegistered {
        Job storage job = _jobs[jobId];

        bytes32 pendingOffer = keccak256(abi.encodePacked(jobId, msg.sender, secret));

        require(getStatus(jobId) == JOB_STATUS_CREATED, ERROR_INVALID_JOB_STATE);
        require(job.pendingOffer == pendingOffer, ERROR_INVALID_VALUE);

        job.worker = msg.sender;
        job.startTime = block.timestamp;

        _profiles[msg.sender].worked.add(jobId);
        _projects[job.token].open.remove(jobId);
        _projects[job.token].filled.add(jobId);

        uint feeQuantity = job.quantity.mul(FEE_BIPS).div(TOTAL_BIPS);
        IERC20(job.token).approve(address(_registry), feeQuantity);
        _registry.rewardStakers(
            msg.sender,
            STAKE_TOKEN,
            job.token,
            feeQuantity
        );
    }

    function end(uint jobId) external {
        Job storage job = _jobs[jobId];

        require(getStatus(jobId) == JOB_STATUS_WORKING, ERROR_INVALID_JOB_STATE);
        require(
            job.manager == msg.sender ||
            job.worker == msg.sender,
            ERROR_NOT_AUTHORIZED
        );

        job.timeRefunded = job.duration.sub(getTimeWorked(jobId));

        refund(jobId, msg.sender);
    }

    function refund(uint jobId, address user) public returns (uint) {
        Job storage job = _jobs[jobId];

        require(getStatus(jobId) == JOB_STATUS_ENDED, ERROR_INVALID_JOB_STATE);
        require(!job.funderRefunded[user], ERROR_NOT_AUTHORIZED);

        (bool funded, uint quantity) = job.funderQuantities.tryGet(user);
        uint refundQuantity = quantity.mul(job.timeRefunded).div(job.duration);
        if (funded) {
            job.funderRefunded[user] = true;

            if (refundQuantity > 0) {
                require(
                    IERC20(job.token).transfer(user, quantity),
                    ERROR_TRANSFER_FAILED
                );
            }
        }
        return refundQuantity;
    }

    function claim(uint jobId, address to) public {
        Job storage job = _jobs[jobId];

        require(job.worker == msg.sender, ERROR_NOT_AUTHORIZED);

        (uint timeOwed, uint moneyOwed) = getTimeAndMoneyOwed(jobId);

        job.timePaid = job.timePaid.add(timeOwed);

        if (moneyOwed > 0) {
            require(
                IERC20(job.token).transfer(to, moneyOwed),
                ERROR_TRANSFER_FAILED
            );
        }
    }

    // Job helpers

    function getStatus(uint jobId) public view returns (uint) {
        Job storage job = _jobs[jobId];

        if (job.timeRefunded > 0) {
            return JOB_STATUS_ENDED;
        } else if (job.worker == address(0)) {
            return JOB_STATUS_CREATED;
        } else if (getTimeWorked(jobId) < job.duration) {
            return JOB_STATUS_WORKING;
        }
        return JOB_STATUS_ENDED;
    }

    function getTimeAndMoneyOwed(uint jobId) public view returns (uint, uint) {
        Job storage job = _jobs[jobId];

        uint timeOwed = getTimeWorked(jobId).sub(job.timePaid);
        uint moneyOwed = job.quantity
            .mul(WORKER_BIPS).div(TOTAL_BIPS)
            .mul(timeOwed).div(job.duration);

        return (timeOwed, moneyOwed);
    }

    function getTimeWorked(uint jobId) public view returns (uint) {
        Job storage job = _jobs[jobId];

        uint timeRefunded = job.timeRefunded;
        if (timeRefunded > 0) {
            return job.duration.sub(timeRefunded);
        } else if (job.worker != address(0)) {
            return Math.min(
                block.timestamp.sub(job.startTime),
                job.duration
            );
        }
        return 0;
    }

    // Job getters

    function getTitle(uint jobId) external view returns (string memory) {
        return _jobs[jobId].title;
    }

    function getDescription(uint jobId) external view returns (string memory) {
        return _jobs[jobId].description;
    }

    function getManager(uint jobId) external view returns (address) {
        return _jobs[jobId].manager;
    }

    function getToken(uint jobId) external view returns (address) {
        return _jobs[jobId].token;
    }

    function getQuantity(uint jobId) external view returns (uint) {
        return _jobs[jobId].quantity;
    }

    function getDuration(uint jobId) external view returns (uint) {
        return _jobs[jobId].duration;
    }

    function getCreateTime(uint jobId) external view returns (uint) {
        return _jobs[jobId].createTime;
    }

    function getPendingManager(uint jobId) external view returns (address) {
        return _jobs[jobId].pendingManager;
    }

    function getPendingOffer(uint jobId) external view returns (bytes32) {
        return _jobs[jobId].pendingOffer;
    }

    function getWorker(uint jobId) external view returns (address) {
        return _jobs[jobId].worker;
    }

    function getStartTime(uint jobId) external view returns (uint) {
        return _jobs[jobId].startTime;
    }

    function getTimePaid(uint jobId) external view returns (uint) {
        return _jobs[jobId].timePaid;
    }

    function getTimeRefunded(uint jobId) external view returns (uint) {
        return _jobs[jobId].timeRefunded;
    }

    function getFunderRefunded(uint jobId, address user) external view returns (bool) {
        return _jobs[jobId].funderRefunded[user];
    }

    function getFunderQuantity(uint jobId, address funder) external view returns (uint) {
        return _jobs[jobId].funderQuantities.get(funder);
    }
    function getFunderQuantities(uint jobId) external view returns (address[] memory, uint[] memory) {
        Job storage job = _jobs[jobId];
        address[] memory funders = job.funderQuantities.keys();
        uint[] memory quantities = new uint[](funders.length);
        for (uint i = 0; i < funders.length; i++) {
            quantities[i] = job.funderQuantities.get(funders[i]);
        }
        return (funders, quantities);
    }
    function getFunderQuantityAt(uint jobId, uint index) external view returns (address, uint) {
        return _jobs[jobId].funderQuantities.at(index);
    }
    function getNumFunderQuantities(uint jobId) external view returns (uint) {
        return _jobs[jobId].funderQuantities.length();
    }

    function getApplicantTimes(uint jobId) external view returns (address[] memory, uint[] memory) {
        Job storage job = _jobs[jobId];
        address[] memory applicants = job.applicantTimes.keys();
        uint[] memory times = new uint[](applicants.length);
        for (uint i = 0; i < applicants.length; i++) {
            times[i] = job.applicantTimes.get(applicants[i]);
        }
        return (applicants, times);
    }
    function getApplicantTimesAt(uint jobId, uint index) external view returns (address, uint) {
        return _jobs[jobId].applicantTimes.at(index);
    }
    function getNumApplicants(uint jobId) external view returns (uint) {
        return _jobs[jobId].applicantTimes.length();
    }

    // Profile getters

    function hasApplied(address user, uint jobId) external view returns (bool) {
        return _profiles[user].appliedTimes.contains(jobId);
    }
    function getAppliedTimes(address user) external view returns (uint[] memory, uint[] memory) {
        Profile storage profile = _profiles[user];
        uint[] memory jobIds = profile.appliedTimes.keys();
        uint[] memory times = new uint[](jobIds.length);
        for (uint i = 0; i < jobIds.length; i++) {
            times[i] = profile.appliedTimes.get(jobIds[i]);
        }
        return (jobIds, times);
    }
    function getAppliedTimesAt(address user, uint index) external view returns (uint, uint) {
        return _profiles[user].appliedTimes.at(index);
    }
    function getNumAppliedTimes(address user) external view returns (uint) {
        return _profiles[user].appliedTimes.length();
    }

    function hasFunded(address user, uint jobId) external view returns (bool) {
        return _profiles[user].fundedTimes.contains(jobId);
    }
    function getFundedTimes(address user) external view returns (uint[] memory, uint[] memory) {
        Profile storage profile = _profiles[user];
        uint[] memory jobIds = profile.fundedTimes.keys();
        uint[] memory times = new uint[](jobIds.length);
        for (uint i = 0; i < jobIds.length; i++) {
            times[i] = profile.fundedTimes.get(jobIds[i]);
        }
        return (jobIds, times);
    }
    function getFundedTimesAt(address user, uint index) external view returns (uint, uint) {
        return _profiles[user].fundedTimes.at(index);
    }
    function getNumFundedTimes(address user) external view returns (uint) {
        return _profiles[user].fundedTimes.length();
    }

    function getManaged(address user) external view returns (uint[] memory) {
        return _profiles[user].managed.values();
    }
    function getManagedAt(address user, uint index) external view returns (uint) {
        return _profiles[user].managed.at(index);
    }
    function getNumManaged(address user) external view returns (uint) {
        return _profiles[user].managed.length();
    }

    function getWorked(address user) external view returns (uint[] memory) {
        return _profiles[user].worked.values();
    }
    function getWorkedAt(address user, uint index) external view returns (uint) {
        return _profiles[user].worked.at(index);
    }
    function getNumWorked(address user) external view returns (uint) {
        return _profiles[user].worked.length();
    }

    // Project getters

    function getOpen(address token) external view returns (uint[] memory) {
        return _projects[token].open.values();
    }
    function getOpenAt(address token, uint index) external view returns (uint) {
        return _projects[token].open.at(index);
    }
    function getNumOpen(address token) external view returns (uint) {
        return _projects[token].open.length();
    }

    function getFilled(address token) external view returns (uint[] memory) {
        return _projects[token].filled.values();
    }
    function getFilledAt(address token, uint index) external view returns (uint) {
        return _projects[token].filled.at(index);
    }
    function getNumFilled(address token) external view returns (uint) {
        return _projects[token].filled.length();
    }

    function getCancelled(address token) external view returns (uint[] memory) {
        return _projects[token].cancelled.values();
    }
    function getCancelledAt(address token, uint index) external view returns (uint) {
        return _projects[token].cancelled.at(index);
    }
    function getNumCancelled(address token) external view returns (uint) {
        return _projects[token].cancelled.length();
    }

    // Token getters
    function getTokens() external view returns (address[] memory) {
        return _tokens.values();
    }
    function getTokenAt(uint index) external view returns (address) {
        return _tokens.at(index);
    }
    function getNumTokens() external view returns (uint) {
        return _tokens.length();
    }
}
