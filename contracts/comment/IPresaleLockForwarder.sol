// SPDX-License-Identifier: UNLICENSED


pragma solidity ^0.8.0;

import "./IERC20Custom.sol";

interface IPresaleLockForwarder {
    function lockLiquidity(
        IERC20Custom _baseToken,
        IERC20Custom _saleToken,
        uint256 _baseAmount,
        uint256 _saleAmount,
        uint256 _unlock_date,
        address payable _withdrawer
    ) external;

    function uniswapPairIsInitialised(address token0, address token1)
        external
        view
        returns (bool);
}
