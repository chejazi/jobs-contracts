// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import "./Directory.sol";

contract JobBoard is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableMap for EnumerableMap.AddressToUintMap;
    using EnumerableMap for EnumerableMap.UintToUintMap;

    struct Job {
        string title;
        string description;
        bytes32 offerHash;
        address manager;
        address worker;
        address token;
        uint quantity;
        uint duration;
        uint commission;
        uint timeCreated;
        uint timeStarted;

        uint _timeEnded;
        uint _timePaid;
        uint _timeRefunded;
        uint _status;

        bool autoRefund;
        mapping(address => bool) userRefunded;

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

    uint private _jobCounter;
    mapping(uint => Job) private _jobs;
    mapping(address => Profile) private _profiles;
    mapping(address => Project) private _projects;

    uint private _commission;
    address private _directory;

    uint public constant JOB_STATUS_CREATED = 1;
    uint public constant JOB_STATUS_WORKING = 2;
    uint public constant JOB_STATUS_ENDED = 3;

    uint public constant MAX_COMMISSION = 1000000;

    modifier isRegistered {
        Directory(_directory).autoRegister(msg.sender);
        _;
    }

    constructor(address directory) {
        _commission = 100000; // 10%
        _directory = directory;
    }

    function create(
        string memory title,
        string memory description,
        address token,
        uint quantity,
        uint duration
    ) external isRegistered {
        uint jobId = ++_jobCounter;
        Job storage job = _jobs[jobId];

        require(duration > 0 && duration < 1000000000, "Invalid job duration");
        require(quantity > 0, "Invalid token quantity");

        job.title = title;
        job.description = description;
        job.token = token;
        job.duration = duration;
        job.commission = _commission;
        job.timeCreated = block.timestamp;

        _profiles[msg.sender].managed.add(jobId);
        _projects[token].open.add(jobId);

        fund(jobId, quantity);
    }

    function describe(uint jobId, string memory description) external {
        Job storage job = _jobs[jobId];

        require(job._status == JOB_STATUS_CREATED, "Job description no longer editable");
        require(job.manager == msg.sender, "Not authorized to update Job");

        job.description = description;
    }

    function fund(uint jobId, uint quantity) public isRegistered nonReentrant {
        Job storage job = _jobs[jobId];

        require(job._status == JOB_STATUS_CREATED, "Job no longer fundable");

        (,uint funderQuantity) = job.funderQuantities.tryGet(msg.sender);

        require(IERC20(job.token).transferFrom(msg.sender, address(this), quantity), "Unable to fund");

        job.funderQuantities.set(msg.sender, funderQuantity.add(quantity));
        job.quantity = job.quantity.add(quantity);

        _profiles[msg.sender].fundedTimes.set(jobId, block.timestamp);
    }

    function apply_(uint jobId) external isRegistered {
        Job storage job = _jobs[jobId];

        require(job._status == JOB_STATUS_CREATED, "Job no longer open");

        _profiles[msg.sender].appliedTimes.set(jobId, block.timestamp);

        if (!job.applicantTimes.contains(msg.sender)) {
            job.applicantTimes.set(msg.sender, block.timestamp);
        }
    }

    function withdraw(uint jobId) external {
        _profiles[msg.sender].appliedTimes.remove(jobId);
    }

    function offer(uint jobId, bytes32 offerHash) external {
        Job storage job = _jobs[jobId];

        require(job._status == JOB_STATUS_CREATED, "Job no longer offerable");
        require(job.manager == msg.sender, "Not Job manager");

        job.offerHash = offerHash;
    }

    function rescind(uint jobId) external {
        Job storage job = _jobs[jobId];

        require(job._status == JOB_STATUS_CREATED, "Job no longer offerable");
        require(job.manager == msg.sender, "Not Job manager");

        job.offerHash = bytes32(0);
    }

    function cancel(uint jobId, bool autoRefund) external {
        Job storage job = _jobs[jobId];

        require(job._status == JOB_STATUS_CREATED, "Job no longer cancelable");

        job._status = JOB_STATUS_ENDED;
        job._timeRefunded = job.duration.sub(getTimeWorked(jobId));

        _projects[job.token].open.remove(jobId);
        _projects[job.token].cancelled.add(jobId);

        if (autoRefund) {
            _refundAll(jobId);
        }
    }

    function accept(uint jobId, string memory secret) external isRegistered {
        Job storage job = _jobs[jobId];

        bytes32 offerHash = keccak256(abi.encodePacked(jobId, msg.sender, secret));

        require(job._status == JOB_STATUS_CREATED, "Job not open");
        require(job.offerHash == offerHash, "Invalid offer");

        job._status = JOB_STATUS_WORKING;
        job.worker = msg.sender;
        job.timeStarted = block.timestamp;

        _profiles[msg.sender].worked.add(jobId);
        _projects[job.token].open.remove(jobId);
        _projects[job.token].filled.add(jobId);

        uint commissionQuantity = job.quantity.mul(job.commission).div(MAX_COMMISSION);
        IERC20(job.token).approve(_directory, commissionQuantity);
        Directory(_directory).commission(
            msg.sender,
            job.token,
            commissionQuantity
        );
    }

    function end(uint jobId, bool autoRefund) external {
        Job storage job = _jobs[jobId];

        require(job._status == JOB_STATUS_WORKING, "Job not open");
        require(
            job.manager == msg.sender ||
            job.worker == msg.sender,
            "Not permitted to end contract"
        );

        job._timeEnded = Math.min(
            block.timestamp,
            job.timeStarted.add(job.duration)
        );
        job._status = JOB_STATUS_ENDED;
        job._timeRefunded = job.duration.sub(getTimeWorked(jobId));

        if (autoRefund && job._timeRefunded > 0) {
            _refundAll(jobId);
        }
    }

    function refund(uint jobId) external nonReentrant {
        Job storage job = _jobs[jobId];

        require(job._status == JOB_STATUS_ENDED, "Job funds locked");
        require(!job.autoRefund, "Refunds already distributed");
        require(!job.userRefunded[msg.sender], "No refund to claim");

        IERC20 token = IERC20(job.token);
        job.userRefunded[msg.sender] = true;

        require(
            token.transfer(
                msg.sender,
                job.funderQuantities.get(msg.sender).mul(job._timeRefunded).div(job.duration)
            ),
            "Unable to refund"
        );
    }

    // Pay out any amount owed to worker
    function claim(uint jobId) public {
        Job storage job = _jobs[jobId];

        require(job.worker == msg.sender, "Not Job worker");

        (uint timeOwed, uint coinOwed) = getUnpaidTimeAndMoney(jobId);

        job._timePaid = job._timePaid.add(timeOwed);

        if (coinOwed > 0) {
            require(IERC20(job.token).transfer(msg.sender, coinOwed), "Unable to transfer token");
        }
    }

    function _refundAll(uint jobId) internal {
        Job storage job = _jobs[jobId];

        job.autoRefund = true;

        IERC20 token = IERC20(job.token);
        uint duration = job.duration;
        uint _timeRefunded = job._timeRefunded;
        EnumerableMap.AddressToUintMap storage funderQuantities = job.funderQuantities;
        address[] memory funders = funderQuantities.keys();
        for (uint i = 0; i < funders.length; i++) {
            address funder = funders[i];
            require(
                token.transfer(
                    funder,
                    funderQuantities.get(funder).mul(_timeRefunded).div(duration)
                ),
                "Unable to refund"
            );
        }
    }

    function setGlobalCommission(uint newCommission) external onlyOwner {
        require(_commission <= MAX_COMMISSION, "Invalid commission");
        _commission = newCommission;
    }

    function getGlobalCommission() external view returns (uint) {
        return _commission;
    }

    function getUnpaidTimeAndMoney(uint jobId) public view returns (uint, uint) {
        Job storage job = _jobs[jobId];

        uint timeOwed = getTimeWorked(jobId).sub(job._timePaid);
        uint coinOwed = job.quantity
                        .mul(MAX_COMMISSION.sub(job.commission)).div(MAX_COMMISSION)
                        .mul(timeOwed).div(job.duration);

        return (timeOwed, coinOwed);
    }

    function getTimeWorked(uint jobId) public view returns (uint) {
        Job storage job = _jobs[jobId];

        if (job._status == JOB_STATUS_WORKING) {
            return Math.min(
                block.timestamp.sub(job.timeStarted),
                job.duration
            );
        } else if (job._status == JOB_STATUS_ENDED) {
            return job._timeEnded.sub(job.timeStarted);
        }
        return 0;
    }

    function getStatus(uint jobId) public view returns (uint) {
        Job storage job = _jobs[jobId];

        if (job._status == JOB_STATUS_WORKING && block.timestamp >= (job.timeStarted.add(job.duration))) {
            return JOB_STATUS_ENDED;
        }
        return job._status;
    }

    function getCommission(uint jobId) external view returns (uint) {
        return _jobs[jobId].commission;
    }

    function getTimeStarted(uint jobId) external view returns (uint) {
        return _jobs[jobId].timeStarted;
    }

    function getAutoRefund(uint jobId) external view returns (bool) {
        return _jobs[jobId].autoRefund;
    }

    function getUserRefunded(uint jobId, address user) external view returns (bool) {
        return _jobs[jobId].userRefunded[user];
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

    function getJob(uint jobId) external view returns (
        string memory title,
        string memory description,
        address manager,
        address worker,
        address token,
        uint quantity,
        uint duration,
        uint timeCreated,
        uint timeWorked,
        uint status,
        bytes32 offerHash
    ) {
        Job storage job = _jobs[jobId];
        title = job.title;
        description = job.description;
        manager = job.manager;
        worker = job.worker;
        token = job.token;
        quantity = job.quantity;
        duration = job.duration;
        timeCreated = job.timeCreated;
        timeWorked = getTimeWorked(jobId);
        status = getStatus(jobId);
        offerHash = job.offerHash;

        return (
            title,
            description,
            manager,
            worker,
            token,
            quantity,
            duration,
            timeCreated,
            timeWorked,
            status,
            offerHash
        );
    }

    function getJobs(uint[] memory jobIds) external view returns (
        string[] memory titles,
        string[] memory descriptions,
        address[] memory managers,
        address[] memory workers,
        address[] memory tokens,
        uint[] memory quantities,
        uint[] memory durations,
        uint[] memory timesCreated,
        uint[] memory timesWorked,
        uint[] memory statuses,
        bytes32[] memory offerHashes
    ) {
        uint n = jobIds.length;
        titles = new string[](n);
        descriptions = new string[](n);
        managers = new address[](n);
        workers = new address[](n);
        tokens = new address[](n);
        quantities = new uint[](n);
        durations = new uint[](n);
        timesCreated = new uint[](n);
        timesWorked = new uint[](n);
        statuses = new uint[](n);
        offerHashes = new bytes32[](n);

        for (n = 0; n < jobIds.length; n++) {
            Job storage job = _jobs[jobIds[n]];
            titles[n] = job.title;
            descriptions[n] = job.description;
            managers[n] = job.manager;
            workers[n] = job.worker;
            tokens[n] = job.token;
            quantities[n] = job.quantity;
            durations[n] = job.duration;
            timesCreated[n] = job.timeCreated;
            timesWorked[n] = getTimeWorked(jobIds[n]);
            statuses[n] = getStatus(jobIds[n]);
            offerHashes[n] = job.offerHash;
        }

        return (
            titles,
            descriptions,
            managers,
            workers,
            tokens,
            quantities,
            durations,
            timesCreated,
            timesWorked,
            statuses,
            offerHashes
        );
    }
}
