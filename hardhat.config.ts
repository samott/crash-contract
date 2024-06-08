import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-foundry";

import type { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox-viem";

const config: HardhatUserConfig = {
	solidity: "0.8.24",
	paths: {
		sources: "./src",
		tests: "./test-ts",
		cache: "./cache",
		artifacts: "./out",
	}
};

export default config;
