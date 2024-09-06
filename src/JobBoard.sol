// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import "./UserAppDirectory.sol";

contract JobBoard is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableMap for EnumerableMap.AddressToUintMap;
    using EnumerableMap for EnumerableMap.UintToUintMap;

    address private constant _feeToken = 0xd21111c0e32df451eb61A23478B438e3d71064CB; // $JOBS

    struct Job {
        string title;
        string description;
        address manager;
        address worker;
        address token;
        uint quantity;
        uint duration;
        uint createTime;
        uint startTime;

        bytes32 _offerHash;
        bool _autoRefunded;
        uint _timeRefunded;
        uint _timePaid;
        uint _status;

        mapping(address => bool) _userRefunded;

        EnumerableMap.AddressToUintMap _funderQuantities;
        EnumerableMap.AddressToUintMap _applicantTimes;
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

    UserAppDirectory private _directory;

    uint public constant JOB_STATUS_CREATED = 1;
    uint public constant JOB_STATUS_WORKING = 2;
    uint public constant JOB_STATUS_ENDED = 3;

    uint private constant FEE_BIPS = 1000; // 10%
    uint private constant WORKER_BIPS = 9000; // 90%
    uint private constant TOTAL_BIPS = 10000; // 100%

    modifier isRegistered {
        _directory.autoRegister(msg.sender);
        _;
    }

    constructor(address directory) {
        _directory = UserAppDirectory(directory);
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
        job.startTime = block.timestamp;

        _profiles[msg.sender].managed.add(jobId);
        _projects[token].open.add(jobId);

        fund(jobId, quantity);
    }

    function update(uint jobId, string memory description) external {
        Job storage job = _jobs[jobId];

        require(job._status == JOB_STATUS_CREATED, "Job description no longer editable");
        require(job.manager == msg.sender, "Not authorized to update Job");

        job.description = description;
    }

    function fund(uint jobId, uint quantity) public isRegistered {
        Job storage job = _jobs[jobId];

        require(job._status == JOB_STATUS_CREATED, "Job no longer fundable");

        (,uint funderQuantity) = job._funderQuantities.tryGet(msg.sender);

        job._funderQuantities.set(msg.sender, funderQuantity.add(quantity));
        job.quantity = job.quantity.add(quantity);

        _profiles[msg.sender].fundedTimes.set(jobId, block.timestamp);

        require(
            IERC20(job.token).transferFrom(msg.sender, address(this), quantity),
            "Unable to fund"
        );
    }

    function apply_(uint jobId) external isRegistered {
        Job storage job = _jobs[jobId];

        require(job._status == JOB_STATUS_CREATED, "Job no longer open");

        _profiles[msg.sender].appliedTimes.set(jobId, block.timestamp);

        if (!job._applicantTimes.contains(msg.sender)) {
            job._applicantTimes.set(msg.sender, block.timestamp);
        }
    }

    function withdraw(uint jobId) external {
        _profiles[msg.sender].appliedTimes.remove(jobId);
    }

    function offer(uint jobId, bytes32 offerHash) external {
        Job storage job = _jobs[jobId];

        require(job._status == JOB_STATUS_CREATED, "Job no longer offerable");
        require(job.manager == msg.sender, "Not Job manager");

        job._offerHash = offerHash;
    }

    function rescind(uint jobId) external {
        Job storage job = _jobs[jobId];

        require(job._status == JOB_STATUS_CREATED, "Job no longer offerable");
        require(job.manager == msg.sender, "Not Job manager");

        job._offerHash = bytes32(0);
    }

    function cancel(uint jobId, bool autoRefund) external {
        Job storage job = _jobs[jobId];

        require(job._status == JOB_STATUS_CREATED, "Job no longer cancelable");

        job._timeRefunded = job.duration;
        job._status = JOB_STATUS_ENDED;

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
        require(job._offerHash == offerHash, "Invalid offer");

        job.worker = msg.sender;
        job.startTime = block.timestamp;
        job._status = JOB_STATUS_WORKING;

        _profiles[msg.sender].worked.add(jobId);
        _projects[job.token].open.remove(jobId);
        _projects[job.token].filled.add(jobId);

        uint feeQuantity = job.quantity.mul(FEE_BIPS).div(TOTAL_BIPS);
        IERC20(job.token).approve(address(_directory), feeQuantity);
        _directory.rewardUserStakers(
            msg.sender,
            _feeToken,
            job.token,
            feeQuantity
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

        job._timeRefunded = job.duration.sub(getTimeWorked(jobId));
        job._status = JOB_STATUS_ENDED;

        if (autoRefund && job._timeRefunded > 0) {
            _refundAll(jobId);
        }
    }

    function refund(uint jobId) external {
        Job storage job = _jobs[jobId];

        require(job._status == JOB_STATUS_ENDED, "Job funds locked");
        require(job._timeRefunded > 0, "Nothing to refund");
        require(!job._autoRefunded, "Refund automatically distributed");
        require(!job._userRefunded[msg.sender], "Refund already claimed");

        job._userRefunded[msg.sender] = true;

        require(
            IERC20(job.token).transfer(
                msg.sender,
                job._funderQuantities.get(msg.sender).mul(job._timeRefunded).div(job.duration)
            ),
            "Unable to refund"
        );
    }

    // Pay out any amount owed to worker
    function claim(uint jobId, address to) public {
        Job storage job = _jobs[jobId];

        require(job.worker == msg.sender, "Not Job worker");

        (uint timeOwed, uint coinOwed) = getUnpaidTimeAndMoney(jobId);

        job._timePaid = job._timePaid.add(timeOwed);

        if (coinOwed > 0) {
            require(
                IERC20(job.token).transfer(to, coinOwed),
                "Unable to transfer token"
            );
        }
    }

    function _refundAll(uint jobId) internal {
        Job storage job = _jobs[jobId];

        job._autoRefunded = true;

        bool success = true;

        uint duration = job.duration;
        uint timeRefunded = job._timeRefunded;
        IERC20 token = IERC20(job.token);

        EnumerableMap.AddressToUintMap storage funderQuantities = job._funderQuantities;
        address[] memory funders = funderQuantities.keys();
        for (uint i = 0; i < funders.length; i++) {
            address funder = funders[i];
            success = success && token.transfer(
                funder,
                funderQuantities.get(funder).mul(timeRefunded).div(duration)
            );
        }
        require(success, "Unable to refund");
    }

    function getUnpaidTimeAndMoney(uint jobId) public view returns (uint, uint) {
        Job storage job = _jobs[jobId];

        uint timeOwed = getTimeWorked(jobId).sub(job._timePaid);
        uint coinOwed = job.quantity
                        .mul(WORKER_BIPS).div(TOTAL_BIPS)
                        .mul(timeOwed).div(job.duration);

        return (timeOwed, coinOwed);
    }

    function getTimeWorked(uint jobId) public view returns (uint) {
        Job storage job = _jobs[jobId];

        if (job._status == JOB_STATUS_WORKING) {
            return Math.min(
                block.timestamp.sub(job.startTime),
                job.duration
            );
        } else if (job._status == JOB_STATUS_ENDED) {
            return job.duration.sub(job._timeRefunded);
        }
        return 0;
    }

    function getStatus(uint jobId) public view returns (uint) {
        Job storage job = _jobs[jobId];

        if (job._status == JOB_STATUS_WORKING && block.timestamp >= (job.startTime.add(job.duration))) {
            return JOB_STATUS_ENDED;
        }
        return job._status;
    }

    function getOfferHash(uint jobId) external view returns (bytes32) {
        return _jobs[jobId]._offerHash;
    }

    function getAutoRefunded(uint jobId) external view returns (bool) {
        return _jobs[jobId]._autoRefunded;
    }

    function getTimeRefunded(uint jobId) external view returns (uint) {
        return _jobs[jobId]._timeRefunded;
    }

    function getTimePaid(uint jobId) external view returns (uint) {
        return _jobs[jobId]._timePaid;
    }

    function getUserRefunded(uint jobId, address user) external view returns (bool) {
        return _jobs[jobId]._userRefunded[user];
    }

    function getFunderQuantity(uint jobId, address funder) external view returns (uint) {
        return _jobs[jobId]._funderQuantities.get(funder);
    }
    function getFunderQuantities(uint jobId) external view returns (address[] memory, uint[] memory) {
        Job storage job = _jobs[jobId];
        address[] memory funders = job._funderQuantities.keys();
        uint[] memory quantities = new uint[](funders.length);
        for (uint i = 0; i < funders.length; i++) {
            quantities[i] = job._funderQuantities.get(funders[i]);
        }
        return (funders, quantities);
    }
    function getFunderQuantityAt(uint jobId, uint index) external view returns (address, uint) {
        return _jobs[jobId]._funderQuantities.at(index);
    }
    function getNumFunderQuantities(uint jobId) external view returns (uint) {
        return _jobs[jobId]._funderQuantities.length();
    }

    function getApplicantTimes(uint jobId) external view returns (address[] memory, uint[] memory) {
        Job storage job = _jobs[jobId];
        address[] memory applicants = job._applicantTimes.keys();
        uint[] memory times = new uint[](applicants.length);
        for (uint i = 0; i < applicants.length; i++) {
            times[i] = job._applicantTimes.get(applicants[i]);
        }
        return (applicants, times);
    }
    function getApplicantTimesAt(uint jobId, uint index) external view returns (address, uint) {
        return _jobs[jobId]._applicantTimes.at(index);
    }
    function getNumApplicants(uint jobId) external view returns (uint) {
        return _jobs[jobId]._applicantTimes.length();
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
        uint createTime,
        uint startTime,
        uint timeWorked,
        uint status
    ) {
        Job storage job = _jobs[jobId];
        title = job.title;
        description = job.description;
        manager = job.manager;
        worker = job.worker;
        token = job.token;
        quantity = job.quantity;
        duration = job.duration;
        createTime = job.createTime;
        startTime = job.startTime;
        timeWorked = getTimeWorked(jobId);
        status = getStatus(jobId);

        return (
            title,
            description,
            manager,
            worker,
            token,
            quantity,
            duration,
            createTime,
            startTime,
            timeWorked,
            status
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
        uint[] memory createTimes,
        uint[] memory startTimes,
        uint[] memory timeWorked,
        uint[] memory statuses
    ) {
        uint n = jobIds.length;
        titles = new string[](n);
        descriptions = new string[](n);
        managers = new address[](n);
        workers = new address[](n);
        tokens = new address[](n);
        quantities = new uint[](n);
        durations = new uint[](n);
        createTimes = new uint[](n);
        startTimes = new uint[](n);
        timeWorked = new uint[](n);
        statuses = new uint[](n);

        for (n = 0; n < jobIds.length; n++) {
            Job storage job = _jobs[jobIds[n]];
            titles[n] = job.title;
            descriptions[n] = job.description;
            managers[n] = job.manager;
            workers[n] = job.worker;
            tokens[n] = job.token;
            quantities[n] = job.quantity;
            durations[n] = job.duration;
            createTimes[n] = job.createTime;
            startTimes[n] = job.startTime;
            timeWorked[n] = getTimeWorked(jobIds[n]);
            statuses[n] = getStatus(jobIds[n]);
        }

        return (
            titles,
            descriptions,
            managers,
            workers,
            tokens,
            quantities,
            durations,
            createTimes,
            startTimes,
            timeWorked,
            statuses
        );
    }
}
