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

    event JobSubmitted(address indexed submitter, uint indexed jobId, address target, uint value, bytes calldatas, uint delay);
    event JobExecuted(address indexed executer, uint indexed jobId);

    // Taken from OpenZeppelin
    function hashJob(
        address target,
        uint value,
        bytes calldatas,
        address submitter,
    ) public pure virtual returns (uint256) {
        return uint256(keccak256(abi.encode(target, value, calldatas, submitter)));
    }

    /**
        * Submit a list of jobs
        * Each job specifies a contract address and a method to call
        * Each job can only be executed after the specified delay
        * Jobs are executed in exchanged for ETH
     */
    function submitJob(address target, uint value, bytes calldatas, uint delay) external payable {
        // validate params
        
        // get job id by hashing job
        uint jobId = hashJob(target, value, calldatas, msg.sender);

        // create job
        Job storage j = jobs[jobId];
        j.id = jobId;
        j.submitter = msg.sender;
        j.bounty = msg.value;
        j.executeAt = block.timestamp + delay;

        emit JobSubmitted(msg.sender, jobId, target, value, calldatas, delay);
    }

    /**
        Spec
        * Caller can execute the given job if the job has not already been executed
        * Caller will receive the bounty associated with the job

        Params
        * jobId
    */
    function executeJob(address target, uint value, bytes calldatas, uint delay) external {
        uint jobId = hashJob(target, value, calldatas, msg.sender);
        Job storage j = jobs[jobId];

        require(j.id > 0, "QuestionH::executeJob: INVALID_JOB");
        require(block.timestamp >= j.executeAt, "QuestionH::executeJob: JOB_INACTIVE");

        (bool success, bytes memory returndata) = target.call{value: value}(calldatas);

        if (success) {
            emit JobExecuted(msg.sender, jobId);
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
}
}