// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract BbtToken is ERC20, ERC20Burnable, ERC20Permit, Ownable2Step {
    uint8 private immutable _decimal;

    constructor()
        ERC20("BabyBoomToken", "BBT")
        ERC20Permit("BabyBoomToken")
        Ownable(msg.sender)
    {
        _decimal = 8;
        _mint(msg.sender, 100_000_000_000 * 10**_decimal); // Mint 100 million tokens to the owner
    }

    function mint(address _to, uint256 _amount) external onlyOwner {
        _mint(_to, _amount);
    }

    function decimals() public view override returns (uint8) {
        return _decimal;
    }
}
