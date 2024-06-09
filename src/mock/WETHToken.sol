// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract WETHToken is ERC20 {
	constructor() ERC20("Wrapped Ether", "WETH") {
		_mint(msg.sender, 10000000000000000000000000000000);
	}

	function decimals() public view virtual override returns (uint8) {
		return 18;
	}
}
