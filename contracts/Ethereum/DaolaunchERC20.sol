// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../Unitls/ERC20.sol";
import "../Unitls/Ownable.sol";

contract DaolaunchERC20 is ERC20, Ownable {
    
    uint8 private _decimmals;

    constructor(string memory name, string memory symbol, uint8 decimals_, uint256 initialSupply) ERC20(name, symbol) {
        _mint(_msgSender(), initialSupply);
        _decimmals = decimals_;
    }
    
    function decimals() public view virtual override returns (uint8) {
        return _decimmals;
    }
    
    function burn(uint256 amount) public {
        _burn(_msgSender(), amount);
    }
}
