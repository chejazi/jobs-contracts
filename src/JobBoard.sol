// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";

interface UserAppDirectory {
    function rewardUserStakers(address user, address stakedToken, address rewardToken, uint quantity) external;
    function autoRegister(address user) external;
}

contract JobBoard {
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableMap for EnumerableMap.AddressToUintMap;
    using EnumerableMap for EnumerableMap.UintToUintMap;

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
        uint _timePaid;
        uint _timeRefunded;
        bool _autoRefunded;
        mapping(address => bool) _claimedRefund;

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

    string private constant ERROR_TRANSFER_FAILED = "Transfer failed";
    string private constant ERROR_NOT_PERMITTED = "Not permitted";
    string private constant ERROR_NO_LONGER_PERFORMABLE = "No longer performable";
    string private constant ERROR_ALREADY_PERFORMED = "Already performed";

    uint public constant JOB_STATUS_CREATED = 1;
    uint public constant JOB_STATUS_WORKING = 2;
    uint public constant JOB_STATUS_ENDED = 3;

    uint public constant FEE_BIPS = 1000; // 10%
    uint public constant WORKER_BIPS = 9000; // 90%
    uint public constant TOTAL_BIPS = 10000; // 100%

    address public constant STAKE_TOKEN = 0xd21111c0e32df451eb61A23478B438e3d71064CB; // $JOBS

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

        require(duration > 0 && duration < 1000000000, "Invalid duration");
        require(quantity > 0, "Invalid token quantity");

        job.title = title;
        job.description = description;
        job.token = token;
        job.duration = duration;
        job.createTime = block.timestamp;

        _profiles[msg.sender].managed.add(jobId);
        _projects[token].open.add(jobId);

        fund(jobId, quantity);
    }

    function update(uint jobId, string memory description) external {
        Job storage job = _jobs[jobId];

        require(getStatus(jobId) == JOB_STATUS_CREATED, ERROR_NO_LONGER_PERFORMABLE);
        require(job.manager == msg.sender, ERROR_NOT_PERMITTED);

        job.description = description;
    }

    function fund(uint jobId, uint quantity) public isRegistered {
        Job storage job = _jobs[jobId];

        require(getStatus(jobId) == JOB_STATUS_CREATED, ERROR_NO_LONGER_PERFORMABLE);

        (,uint funderQuantity) = job._funderQuantities.tryGet(msg.sender);

        job._funderQuantities.set(msg.sender, funderQuantity.add(quantity));
        job.quantity = job.quantity.add(quantity);

        _profiles[msg.sender].fundedTimes.set(jobId, block.timestamp);

        require(
            IERC20(job.token).transferFrom(msg.sender, address(this), quantity),
            ERROR_TRANSFER_FAILED
        );
    }

    function apply_(uint jobId) external isRegistered {
        Job storage job = _jobs[jobId];

        require(getStatus(jobId) == JOB_STATUS_CREATED, ERROR_NO_LONGER_PERFORMABLE);

        _profiles[msg.sender].appliedTimes.set(jobId, block.timestamp);

        if (!job._applicantTimes.contains(msg.sender)) {
            job._applicantTimes.set(msg.sender, block.timestamp);
        }
    }

    function remove(uint jobId) external {
        _profiles[msg.sender].appliedTimes.remove(jobId);
    }

    function offer(uint jobId, bytes32 offerHash) public {
        Job storage job = _jobs[jobId];

        require(getStatus(jobId) == JOB_STATUS_CREATED, ERROR_NO_LONGER_PERFORMABLE);
        require(job.manager == msg.sender, ERROR_NOT_PERMITTED);

        job._offerHash = offerHash;
    }

    function rescind(uint jobId) external {
        offer(jobId, bytes32(0));
    }

    function cancel(uint jobId, bool autoRefund) external {
        Job storage job = _jobs[jobId];

        require(getStatus(jobId) == JOB_STATUS_CREATED, ERROR_NO_LONGER_PERFORMABLE);

        job._timeRefunded = job.duration;

        _projects[job.token].open.remove(jobId);
        _projects[job.token].cancelled.add(jobId);

        if (autoRefund) {
            _refundAll(job);
        }
    }

    function accept(uint jobId, string memory secret) external isRegistered {
        Job storage job = _jobs[jobId];

        bytes32 offerHash = keccak256(abi.encodePacked(jobId, msg.sender, secret));

        require(getStatus(jobId) == JOB_STATUS_CREATED, ERROR_NO_LONGER_PERFORMABLE);
        require(job._offerHash == offerHash, "Invalid offer");

        job.worker = msg.sender;
        job.startTime = block.timestamp;
        job._offerHash = bytes32(0);

        _profiles[msg.sender].worked.add(jobId);
        _projects[job.token].open.remove(jobId);
        _projects[job.token].filled.add(jobId);

        uint feeQuantity = job.quantity.mul(FEE_BIPS).div(TOTAL_BIPS);
        IERC20(job.token).approve(address(_directory), feeQuantity);
        _directory.rewardUserStakers(
            msg.sender,
            STAKE_TOKEN,
            job.token,
            feeQuantity
        );
    }

    function end(uint jobId, bool autoRefund) external {
        Job storage job = _jobs[jobId];

        require(getStatus(jobId) == JOB_STATUS_WORKING, ERROR_NO_LONGER_PERFORMABLE);
        require(
            job.manager == msg.sender ||
            job.worker == msg.sender,
            ERROR_NOT_PERMITTED
        );

        job._timeRefunded = job.duration.sub(getTimeWorked(jobId));

        if (autoRefund) {
            _refundAll(job);
        }
    }

    function refund(uint jobId) external {
        Job storage job = _jobs[jobId];

        require(getStatus(jobId) == JOB_STATUS_ENDED, "Job still active");
        require(
            !job._autoRefunded &&
            !job._claimedRefund[msg.sender],
            ERROR_ALREADY_PERFORMED
        );

        job._claimedRefund[msg.sender] = true;

        uint quantity = job._funderQuantities.get(msg.sender).mul(job._timeRefunded).div(job.duration);
        if (quantity > 0) {
            require(
                IERC20(job.token).transfer(msg.sender, quantity),
                ERROR_TRANSFER_FAILED
            );
        }
    }

    function claim(uint jobId, address to) public {
        Job storage job = _jobs[jobId];

        require(job.worker == msg.sender, ERROR_NOT_PERMITTED);

        (uint timeOwed, uint coinOwed) = getUnpaidTimeAndMoney(jobId);

        job._timePaid = job._timePaid.add(timeOwed);

        if (coinOwed > 0) {
            require(
                IERC20(job.token).transfer(to, coinOwed),
                ERROR_TRANSFER_FAILED
            );
        }
    }

    function _refundAll(Job storage job) internal {
        job._autoRefunded = true;

        uint timeRefunded = job._timeRefunded;
        if (timeRefunded > 0) {
            EnumerableMap.AddressToUintMap storage funderQuantities = job._funderQuantities;
            address[] memory funders = funderQuantities.keys();
            IERC20 token = IERC20(job.token);
            uint duration = job.duration;

            bool success = true;
            for (uint i = 0; i < funders.length; i++) {
                address funder = funders[i];
                uint quantity = funderQuantities.get(funder).mul(timeRefunded).div(duration);
                if (quantity > 0) {
                    success = success && token.transfer(funder, quantity);
                }
            }
            require(success, ERROR_TRANSFER_FAILED);
        }
    }

    function getStatus(uint jobId) public view returns (uint) {
        Job storage job = _jobs[jobId];

        if (job._timeRefunded > 0) {
            return JOB_STATUS_ENDED;
        } else if (job.worker == address(0)) {
            return JOB_STATUS_CREATED;
        } else if (getTimeWorked(jobId) < job.duration) {
            return JOB_STATUS_WORKING;
        }
        return JOB_STATUS_ENDED;
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

        uint timeRefunded = job._timeRefunded;
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

    function getOfferHash(uint jobId) external view returns (bytes32) {
        return _jobs[jobId]._offerHash;
    }

    function hasAutoRefunded(uint jobId) external view returns (bool) {
        return _jobs[jobId]._autoRefunded;
    }

    function hasClaimedRefund(uint jobId, address user) external view returns (bool) {
        return _jobs[jobId]._claimedRefund[user];
    }

    function getFunderRefund(uint jobId, address funder) external view returns (uint) {
        Job storage job = _jobs[jobId];
        return job._funderQuantities.get(funder).mul(job._timeRefunded).div(job.duration);
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

    function getStaff(uint jobId) external view returns (address, address) {
        Job storage job = _jobs[jobId];
        return (job.manager, job.worker);
    }

    function getCompensation(uint jobId) external view returns (address, uint, uint) {
        Job storage job = _jobs[jobId];
        return (
            job.token,
            job.quantity,
            job.duration
        );
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
