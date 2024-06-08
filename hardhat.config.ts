import "@nomicfoundation/hardhat-toolbox-viem";
import "@nomicfoundation/hardhat-foundry";

import type { HardhatUserConfig } from "hardhat/config";

const config: HardhatUserConfig = {
	solidity: "0.8.25",
	paths: {
		sources: "./src",
		tests: "./test-ts",
		cache: "./cache",
		artifacts: "./out",
	}
};

export default config;
