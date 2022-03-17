// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

contract QuestionH {
    /** QUESTIONS
        
        1. Do users need to be able to submit multiple jobs in a single transaction, or just one job per transaction?
     */

    struct Job {
        uint id;
        address submitter;
        uint bounty;
        uint executeAt;
        bool executed;
    }

    mapping(uint => Job) jobs;
    bool executing;

    event JobSubmitted(address indexed submitter, uint indexed jobId, address target, uint value, bytes calldatas, uint delay);
    event JobExecuted(address indexed executer, uint indexed jobId);

    // Taken from OpenZeppelin
    function hashJob(
        address target,
        uint value,
        bytes calldata calldatas,
        uint delay,
        address submitter
    ) public pure virtual returns (uint256) {
        return uint256(keccak256(abi.encode(target, value, calldatas, delay, submitter)));
    }

    /**
        * @dev Submits a job
        *
        * Each job specifies a contract address and a method to call + associated call data,
        * and how much time has to pass before the job can be executed (i.e. 'delay').
        * 
        * Jobs are executed in exchanged for ETH, the amount of which is determined by the
        * amount of ETH deposited to the contract via this transaction.
     */
    function submitJob(address target, uint value, bytes calldata calldatas, uint delay) external payable {        
        /**
            * @dev Prevent jobs that would have this contract create jobs with the bounty
            * coming from this contract's funds.
            *
            * This exploit could be used to drain the contract's funds.
         */
        require(target != address(this), "QuestionH::submitJob: INVALID_TARGET");

        /**
            * @dev Get job id by hashing job
            *
            * This is a gas-optimized method for storing the job data on-chain.
            *
            * See executeJob() to see how the on-chain job data is consumed.
         */
        uint jobId = hashJob(target, value, calldatas, delay, msg.sender);

        // create job
        Job storage j = jobs[jobId];
        j.id = jobId;
        j.submitter = msg.sender;
        j.bounty = msg.value;
        j.executeAt = block.timestamp + delay;

        /**
            * NOTE: executeJob() below requires the same params used to submit a job
            * in order to find the job's id.
            *
            * I'm not sure what best practice here would be. These values could be stored
            * in a centralized DB or decentralized storage solution from the application layer.
            * This solution would be more gas-efficient but an error here could make the given
            * job's params difficult to retrieve.
         */
        emit JobSubmitted(msg.sender, jobId, target, value, calldatas, delay);
    }

    /**
        * @dev Execute a submitted job
        *
        * Requirements:
        * - Given params have to correspond to a previously submitted job.
        * - Caller can only execute a job if the job's delay has expired.
        * - Caller can only execute the given job if the job has not already been executed.
        * 
        * Caller will receive the bounty associated with the job.
    */
    function executeJob(address target, uint value, bytes calldata calldatas, uint delay) external {
        uint jobId = hashJob(target, value, calldatas, delay, msg.sender);
        Job storage j = jobs[jobId];

        require(j.id > 0, "QuestionH::executeJob: INVALID_JOB");
        require(block.timestamp >= j.executeAt, "QuestionH::executeJob: JOB_INACTIVE");
        require(!j.executed, "QuestionH::executeJob: JOB_ALREADY_EXECUTED");
        // This should prevent reentrancy attacks
        require(!executing, "QuestionH:executeJob: CURRENTLY_EXECUTING");

        // Second protection against reentrancy attacks
        j.executed = true;
        executing = true;

        (bool success, bytes memory returndata) = target.call{value: value}(calldatas);

        if (success) {
            emit JobExecuted(msg.sender, jobId);
            msg.sender.call{value: j.bounty}("");
        } else if (returndata.length > 0) {
            // Taken from OZ's Address.sol contract
            assembly {
                let returndata_size := mload(returndata)
                revert(add(32, returndata), returndata_size)
            }
        }
        else {
            // No revert reason given
            revert("Call reverted without message");
        }

        executing = false;
    }    
}