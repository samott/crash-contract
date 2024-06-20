// Crash game - treasury/deposit contract
//
// Author: Shaun Amott <shaun@inerd.com>
//
// SPDX-License-Identifier: BSD-2-Clause

pragma solidity ^0.8.25;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

error InvalidTaskTypeError();
error InvalidSignatureError();
error RequestNotFromUserError();
error InvalidCoinId();

contract Crash is Ownable, EIP712 {
	address public agentAddress;

	enum TaskType {
		CREDIT,
		DEBIT
	}

	struct Task{
		TaskType taskType;
		address user;
		uint32 coinId;
		uint256 amount;
		uint256 nonce;
	}

	struct WithdrawalRequest {
		address user;
		uint32 coinId;
		uint256 amount;
		uint256 nonce;
		Task[] tasks;
	}

	mapping(uint32 => IERC20) public supportedCoins;

	mapping(uint32 => uint256) public contractBalances;
	mapping(uint256 => uint256) private userBalances;
	mapping(address => uint256) public nonces;

	event BalanceIncreased(
		address user,
		uint32 coinId,
		uint256 amount,
		uint256 newBalance
	);

	event BalanceDecreased(
		address user,
		uint32 coinId,
		uint256 amount,
		uint256 newBalance
	);

	/**
	 * Requires a valid coin. Throws an exception if the coin is not valid.
	 *
	 * @param coinId The coin to check.
	 */
	modifier onlyValidCoin(uint32 coinId) {
		if (coinId == 0 || address(supportedCoins[coinId]) == address(0)) {
			revert InvalidCoinId();
		}
		_;
	}

	constructor(
		address initialAgentAddress
	)
		EIP712("Crash", "1.0")
		Ownable(msg.sender)
	{
		agentAddress = initialAgentAddress;
	}

	/**
	 * Assigns a new agent address. Implicitly invalidates
	 * any outstanding signed requests.
	 *
	 * @param newAgentAddress New address.
	 */
	function setAgentAddress(
		address newAgentAddress
	)
		public
		onlyOwner
	{
		agentAddress = newAgentAddress;
	}

	/**
	 * Adds a supported coin (ERC20 token)
	 *
	 * @param coinId Unique ID to assign to this taken.
	 * @param token  Address of token to add.
	 */
	function addCoin(
		uint32 coinId,
		IERC20 token
	)
		public
		onlyOwner
	{
		require(address(supportedCoins[coinId]) == address(0), "coinId already assigned");
		supportedCoins[coinId] = token;
	}

	function getUserBalance(
		address user,
		uint32 coinId
	)
		public
		onlyValidCoin(coinId)
		view
		returns (uint256)
	{
		uint256 balId = encodeBalanceId(user, coinId);
		return userBalances[balId];
	}

	/**
	 * Executes a withdrawal request prepared by the contract
	 * agent. The agent may give the user housekeeping work to
	 * do (adjusting balances of other users) prior to releasing
	 * funds.
	 *
	 * @param req       Withdrawal request.
	 * @param signature EIP712 signature of req.
	 */
	function withdraw(
		WithdrawalRequest calldata req,
		bytes calldata signature
	)
		public
	{
		if (req.user != msg.sender)
			revert RequestNotFromUserError();

		validateWithdrawalSignature(req, signature);
		executeTasks(req.tasks);
		debitBalance(req.user, req.coinId, req.amount);

		IERC20 token = IERC20(supportedCoins[req.coinId]);
		require(token.transfer(req.user, req.amount), "Transfer failed");
	}

	/**
	 * Transfers tokens from the caller's wallet to the
	 * contract and updates the caller's balance record.
	 *
	 * @param coinId Coin to deposit.
	 * @param amount Number of tokens to transfer.
	 */
	function deposit(
		uint32 coinId,
		uint256 amount
	)
		public
		onlyValidCoin(coinId)
	{
		uint256 balId = encodeBalanceId(msg.sender, coinId);

		userBalances[balId] += amount;

		IERC20 token = IERC20(supportedCoins[coinId]);
		require(token.allowance(msg.sender, address(this)) >= amount, "Transfer not approved");
		require(token.transferFrom(msg.sender, address(this), amount), "Transfer failed");

		emit BalanceIncreased(
			msg.sender,
			coinId,
			amount,
			userBalances[balId]
		);
	}

	/**
	 * Takes the specified amount of tokens of the given
	 * coin from the available contract balance and assigns
	 * it to the specified user.
	 *
	 * @param user   User to debit.
	 * @param coinId ID of token.
	 * @param amount Amount to debit.
	 */
	function creditBalance(
		address user,
		uint32 coinId,
		uint256 amount
	)
		internal
	{
		uint256 balId = encodeBalanceId(user, coinId);

		contractBalances[coinId] -= amount;
		userBalances[balId] += amount;

		emit BalanceIncreased(
			user,
			coinId,
			amount,
			userBalances[balId]
		);
	}

	/**
	 * Takes the specified amount of tokens of the given
	 * coin from the user's balance and moves it to the
	 * contract's available balance.
	 *
	 * @param user   User to debit.
	 * @param coinId ID of token.
	 * @param amount Amount to debit.
	 */
	function debitBalance(
		address user,
		uint32 coinId,
		uint256 amount
	)
		internal
	{
		uint256 balId = encodeBalanceId(user, coinId);

		userBalances[balId] -= amount;
		contractBalances[coinId] += amount;

		emit BalanceIncreased(
			user,
			coinId,
			amount,
			userBalances[balId]
		);
	}

	/**
	 * Given a list of housekeeping tasks, iterates
	 * over the list and performs each task in order,
	 * if it hasn't already been performed.
	 *
	 * @param tasks List of tasks.
	 */
	function executeTasks(
		Task[] calldata tasks
	)
		internal
	{
		for (uint256 i = 0; i < tasks.length; i++) {
			if (tasks[i].nonce >= nonces[tasks[i].user])
				continue;

			if (tasks[i].taskType == TaskType.DEBIT) {
				debitBalance(
					tasks[i].user,
					tasks[i].coinId,
					tasks[i].amount
				);
			} else if (tasks[i].taskType == TaskType.CREDIT) {
				creditBalance(
					tasks[i].user,
					tasks[i].coinId,
					tasks[i].amount
				);
			} else {
				revert InvalidTaskTypeError();
			}

			nonces[tasks[i].user]++;
		}
	}

	/**
	 * Verifies that the given signature matches the
	 * given request, and that the contract's agent
	 * address was the signer of the request. Reverts
	 * otherwise.
	 *
	 * @param req       Request that was signed.
	 * @param signature Signature to verify.
	 */
	function validateWithdrawalSignature(
		WithdrawalRequest calldata req,
		bytes calldata signature
	)
		internal
		view
	{
		bytes32 digest = _hashTypedDataV4(keccak256(abi.encode(
			keccak256("WithdrawalRequest(address user,uint32 coinId,uint256 amount,uint256 nonce,Task[] tasks)Task(uint8 taskType,address user,uint32 coinId,uint256 amount,uint256 nonce)"),
			req.user,
			req.coinId,
			req.amount,
			req.nonce,
			hashTasks(req.tasks)
		)));

		address signer = ECDSA.recover(digest, signature);

		if (signer != agentAddress)
			revert InvalidSignatureError();
	}

	/**
	 * Returns a hash of the given task.
	 *
	 * @param  task Task.
	 *
	 * @return hash Hash.
	 */
	function hashTask(
		Task calldata task
	)
		private
		pure
		returns (bytes32)
	{
		return keccak256(abi.encode(
			keccak256("Task(uint8 taskType,address user,uint32 coinId,uint256 amount,uint256 nonce)"),
			task.taskType,
			task.user,
			task.coinId,
			task.amount,
			task.nonce
		));
	}

	/**
	 * Returns a hash of the given tasks.
	 *
	 * @param  tasks Array of tasks.
	 *
	 * @return hash  Hash.
	 */
	function hashTasks(
		Task[] calldata tasks
	)
		private
		pure
		returns (bytes32)
	{
		bytes memory data;

		uint256 numTasks = tasks.length;

		for (uint256 i = 0; i < numTasks; i++)
			data = bytes.concat(data, hashTask(tasks[i]));

		bytes32 hash = keccak256(data);
		return hash;
	}

	/**
	 * Encodes the given user and coinId into a value that indexes
	 * the balances map.
	 *
	 * @param user   Owner of this balance.
	 * @param coinId Coin to which the balance refers.
	 *
	 * @return balId Encoded balance ID.
	 */
	function encodeBalanceId(
		address user,
		uint32 coinId
	)
		internal
		pure
		returns (uint256)
	{
		return uint256(bytes32(abi.encodePacked(user, coinId)));
	}
}
