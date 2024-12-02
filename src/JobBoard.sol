// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import "./IJobBoard.sol";
import "./IRegistry.sol";

contract JobBoard is IJobBoard {
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
        address pendingWorker;

        address worker;
        uint startTime;
        uint timePaid;
        uint timeRefunded;

        EnumerableMap.AddressToUintMap funderQuantities;
        EnumerableMap.AddressToUintMap applicantTimes;

        address board;
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

    EnumerableSet.UintSet private _open;
    EnumerableSet.UintSet private _filled;
    EnumerableSet.UintSet private _cancelled;

    IRegistry private constant _registry = IRegistry(0x4011AaBAD557be4858E08496Db5B1f506a4e6167);

    string private constant ERROR_TRANSFER_FAILED   = "Transfer failed";
    string private constant ERROR_NOT_AUTHORIZED    = "Not authorized";
    string private constant ERROR_INVALID_JOB_STATE = "Invalid job state";
    string private constant ERROR_INVALID_VALUE     = "Invalid value";

    uint public constant JOB_STATUS_CREATED = 1;
    uint public constant JOB_STATUS_WORKING = 2;
    uint public constant JOB_STATUS_ENDED   = 3;

    uint public constant FEE_BIPS =     1000; // 10%
    uint public constant WORKER_BIPS =  9000; // 90%
    uint public constant TOTAL_BIPS =  10000; // 100%

    uint public constant MAX_FUNDERS =  100;

    uint public counter;

    address public constant STAKE_TOKEN = 0xd21111c0e32df451eb61A23478B438e3d71064CB; // $JOBS

    modifier isRegistered {
        _registry.autoRegister(msg.sender);
        _;
    }

    constructor() {
        JobBoard board = JobBoard(0xDC324998F1cbf814e5e4Fa29C60Be0778A1B702A);
        uint numOldJobs = board.counter();
        for (uint i = 1; i <= numOldJobs; i++) {
            Job storage job = _jobs[i];
            job.title = board.getTitle(i);
            job.description = board.getDescription(i);
            job.manager = board.getManager(i);
            job.token = board.getToken(i);
            job.quantity = board.getQuantity(i);
            job.duration = board.getDuration(i);
            job.createTime = board.getCreateTime(i);
            job.worker = board.getWorker(i);
            job.startTime = board.getStartTime(i);
            job.board = address(board);
            _profiles[job.manager].managed.add(i);
            if (job.worker != address(0)) {
                job.timePaid = job.duration;
                _filled.add(i);
                _projects[job.token].filled.add(i);
                _profiles[job.worker].worked.add(i);
            } else {
                job.timeRefunded = job.duration;
                _cancelled.add(i);
                _projects[job.token].cancelled.add(i);
            }
            _tokens.add(job.token);
        }
        counter = numOldJobs;
    }

    function create(string memory title, string memory description, address token, uint quantity, uint duration) external isRegistered returns (uint) {
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
        job.board = address(this);

        _profiles[msg.sender].managed.add(jobId);
        _projects[token].open.add(jobId);
        _tokens.add(token);
        _open.add(jobId);

        fund(jobId, quantity);

        return jobId;
    }

    function updateDescription(uint jobId, string memory description) external {
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

    function manage(uint jobId) external isRegistered {
        Job storage job = _jobs[jobId];

        require(getStatus(jobId) != JOB_STATUS_ENDED, ERROR_INVALID_JOB_STATE);
        require(job.pendingManager == msg.sender, ERROR_NOT_AUTHORIZED);

        job.manager = msg.sender;
        _profiles[msg.sender].managed.add(jobId);
    }

    function fund(uint jobId, uint quantity) public isRegistered {
        Job storage job = _jobs[jobId];

        require(getStatus(jobId) == JOB_STATUS_CREATED, ERROR_INVALID_JOB_STATE);
        require(quantity > 0, ERROR_INVALID_VALUE);

        (,uint funderQuantity) = job.funderQuantities.tryGet(msg.sender);
        job.funderQuantities.set(msg.sender, funderQuantity + quantity);
        job.quantity += quantity;
        _profiles[msg.sender].fundedTimes.set(jobId, block.timestamp);

        require(job.funderQuantities.length() <= MAX_FUNDERS, "Max funders reached");
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

    function unapply(uint jobId) external {
        _profiles[msg.sender].appliedTimes.remove(jobId);
        _jobs[jobId].applicantTimes.remove(msg.sender);
    }

    function cancel(uint jobId) external {
        Job storage job = _jobs[jobId];

        require(getStatus(jobId) == JOB_STATUS_CREATED, ERROR_INVALID_JOB_STATE);
        require(job.manager == msg.sender, ERROR_NOT_AUTHORIZED);

        job.pendingManager = address(0);
        job.pendingWorker = address(0);
        job.timeRefunded = job.duration;

        _projects[job.token].open.remove(jobId);
        _projects[job.token].cancelled.add(jobId);
        _open.remove(jobId);
        _cancelled.add(jobId);

        _refund(jobId);
    }

    function offer(uint jobId, address candidate) external {
        Job storage job = _jobs[jobId];

        require(getStatus(jobId) == JOB_STATUS_CREATED, ERROR_INVALID_JOB_STATE);
        require(job.manager == msg.sender, ERROR_NOT_AUTHORIZED);

        job.pendingWorker = candidate;
    }

    function rescind(uint jobId) external {
        Job storage job = _jobs[jobId];

        require(getStatus(jobId) == JOB_STATUS_CREATED, ERROR_INVALID_JOB_STATE);
        require(job.manager == msg.sender, ERROR_NOT_AUTHORIZED);

        job.pendingWorker = address(0);
    }

    function accept(uint jobId) external isRegistered {
        Job storage job = _jobs[jobId];

        require(getStatus(jobId) == JOB_STATUS_CREATED, ERROR_INVALID_JOB_STATE);
        require(job.pendingWorker == msg.sender, ERROR_INVALID_VALUE);

        job.worker = msg.sender;
        job.startTime = block.timestamp;
        job.pendingWorker = address(0);

        _profiles[msg.sender].worked.add(jobId);
        _projects[job.token].open.remove(jobId);
        _projects[job.token].filled.add(jobId);
        _open.remove(jobId);
        _filled.add(jobId);

        uint feeQuantity = job.quantity * FEE_BIPS / TOTAL_BIPS;
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

        job.timeRefunded = job.duration - getTimeWorked(jobId);

        _refund(jobId);
    }

    function claim(uint jobId, address to) external {
        Job storage job = _jobs[jobId];

        require(job.worker == msg.sender, ERROR_NOT_AUTHORIZED);

        (uint timeOwed, uint moneyOwed) = getTimeAndMoneyOwed(jobId);

        job.timePaid += timeOwed;

        if (moneyOwed > 0) {
            require(
                IERC20(job.token).transfer(to, moneyOwed),
                ERROR_TRANSFER_FAILED
            );
        }
    }

    function _refund(uint jobId) internal {
        Job storage job = _jobs[jobId];

        require(getStatus(jobId) == JOB_STATUS_ENDED, ERROR_INVALID_JOB_STATE);

        EnumerableMap.AddressToUintMap storage funderQuantities = job.funderQuantities;
        address[] memory funders = funderQuantities.keys();
        uint timeRefunded = job.timeRefunded;
        uint duration = job.duration;
        address token = job.token;
        for (uint256 i = 0; i < funders.length; i++) {
            uint refund = job.funderQuantities.get(funders[i]) * timeRefunded / duration;

            if (refund > 0) {
                require(
                    IERC20(token).transfer(funders[i], refund),
                    ERROR_TRANSFER_FAILED
                );
            }
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

        uint timeOwed = getTimeWorked(jobId) - job.timePaid;
        uint moneyOwed = job.quantity
            * WORKER_BIPS / TOTAL_BIPS
            * timeOwed / job.duration;

        return (timeOwed, moneyOwed);
    }

    function getTimeWorked(uint jobId) public view returns (uint) {
        Job storage job = _jobs[jobId];

        uint timeRefunded = job.timeRefunded;
        if (timeRefunded > 0) {
            return job.duration - timeRefunded;
        } else if (job.worker != address(0)) {
            return Math.min(
                block.timestamp - job.startTime,
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

    function getPendingWorker(uint jobId) external view returns (address) {
        return _jobs[jobId].pendingWorker;
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

    function getBoard(uint jobId) external view returns (address) {
        return _jobs[jobId].board;
    }

    // Profile getters

    function hasApplied(address user, uint jobId) public view returns (bool) {
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

    function getOpen() external view returns (uint[] memory) {
        return _open.values();
    }
    function getOpenAt(uint index) external view returns (uint) {
        return _open.at(index);
    }
    function getNumOpen() external view returns (uint) {
        return _open.length();
    }

    function getFilled() external view returns (uint[] memory) {
        return _filled.values();
    }
    function getFilledAt(uint index) external view returns (uint) {
        return _filled.at(index);
    }
    function getNumFilled() external view returns (uint) {
        return _filled.length();
    }

    function getCancelled() external view returns (uint[] memory) {
        return _cancelled.values();
    }
    function getCancelledAt(uint index) external view returns (uint) {
        return _cancelled.at(index);
    }
    function getNumCancelled() external view returns (uint) {
        return _cancelled.length();
    }

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
