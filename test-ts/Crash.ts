import { expect } from "chai";
import hre from "hardhat";

import {
	PublicClient,
	parseUnits,
	formatUnits,
	zeroAddress,
} from "viem";

type Contract = Awaited<ReturnType<typeof hre.viem.getContractAt>>;
type Client = Awaited<ReturnType<typeof hre.viem.getWalletClients>>[number];

type CoinDef = {
	contract?: Contract,
	coinId: number
};

describe("Crash", () => {
	let crashContract: any;
	let owner: Client;
	let agent: Client;
	let user1: Client;
	let publicClient: PublicClient;

	const coins: Record<string, CoinDef> = {
		weth: {
			coinId: 1
		}
	}

	const contractAs = async (
		client: Client,
		contractName: string = 'Crash',
		contract: Contract = crashContract
	) => {
		if (!client.account)
			throw new Error('Account not defined');

		return await hre.viem.getContractAt(
			contractName,
			contract.address,
			{ client: { wallet: client } }
		);
	}

	describe('Deployment', () => {
		it('Should set up the contract', async () => {
			[owner, agent, user1] = await hre.viem.getWalletClients();
			publicClient = await hre.viem.getPublicClient();
			crashContract = await hre.viem.deployContract("Crash", [zeroAddress], {});
		});

		it('Should set the agent address', async () => {
			await crashContract.write.setAgentAddress([agent.account?.address]);
			const newAddress = await crashContract.read.agentAddress();
			expect(newAddress.toLowerCase()).to.equal(agent.account?.address.toLowerCase());
		});

		it('Should deploy a mock WETH contract', async () => {
			coins.weth.contract = await hre.viem.deployContract("WETHToken", [], {});
		});

		it('Should configure WETH as a supported coin', async () => {
			await crashContract.write.addCoin([coins.weth.coinId, coins.weth?.contract?.address]);
			const coinAddress = await crashContract.read.supportedCoins([ coins.weth.coinId ]);
			expect(coinAddress.toLowerCase()).to.equal(coins.weth.contract!.address.toLowerCase());
		});
	});

	describe('Set up user', () => {
		it('Should give user some WETH', async () => {
			const amount = '10';

			await coins.weth.contract!.write.transfer([ user1.account!.address, parseUnits(amount, 18) ]);

			const newBalance = await coins.weth.contract!.read.balanceOf([ user1.account!.address ]);

			expect(formatUnits(newBalance, 18)).to.equal(amount);
		});
	});

	describe('User interaction', () => {
		it('Should deposit tokens to the contract', async () => {
			const contractAsUser1 = await contractAs(user1);
			const wethAsUser1 = await contractAs(user1, "WETHToken", coins.weth.contract);

			const amount = '0.01';

			await wethAsUser1.write.approve([ crashContract.address, parseUnits(amount, 18) ]);

			await contractAsUser1.write.deposit([ coins.weth.coinId, parseUnits(amount, 18) ]);
		});
	});

	describe('Withdrawal', () => {
		it('Should withdraw user funds with permission', async () => {
			const domain = {
				name: 'Crash',
				version: '1.0',
				chainId: 31337,
				verifyingContract: crashContract.address,
			};

			const types = {
				WithdrawalRequest: [
					{ name: 'user', type: 'address' },
					{ name: 'coinId', type: 'uint32' },
					{ name: 'amount', type: 'uint256' },
					{ name: 'nonce', type: 'uint256' },
					{ name: 'tasks', type: 'Task[]' },
				],
				Task: [
					{ name: 'taskType', type: 'uint8' },
					{ name: 'user', type: 'address' },
					{ name: 'coinId', type: 'uint32' },
					{ name: 'amount', type: 'uint256' },
					{ name: 'nonce', type: 'uint256' },
				]
			};

			const request = {
				user: user1.account.address,
				coinId: coins.weth.coinId,
				amount: '1',
				nonce: 0,
				tasks: []
			};

			const signature = await agent.signTypedData({
				domain,
				types,
				primaryType: 'WithdrawalRequest',
				message: request
			});

			const contractBalanceBefore = await crashContract.read.getUserBalance([
				user1.account.address,
				coins.weth.coinId
			]);

			const walletBalanceBefore = await coins.weth.contract!.read.balanceOf([
				user1.account.address,
			]);

			const contractAsUser1 = await contractAs(user1);
			await contractAsUser1.write.withdraw([ request, signature ]);

			const contractBalanceAfter = await crashContract.read.getUserBalance([
				user1.account.address,
				coins.weth.coinId
			]);

			const walletBalanceAfter = await coins.weth.contract!.read.balanceOf([
				user1.account.address,
			]);

			expect(contractBalanceBefore - contractBalanceAfter).to.equal(1n);
			expect(walletBalanceAfter - walletBalanceBefore).to.equal(1n);
		});
	});
});
