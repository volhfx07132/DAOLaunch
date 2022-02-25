// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../common/IERC20Custom.sol";
import "../common/TransferHelper.sol";
import "../common/IPresaleFactory.sol";
import "../common/IUniswapV2Locker.sol";
import "../common/IUniswapV2Factory.sol";
import "../common/IUniswapV2Pair.sol";

contract PresaleLockForwarder is Ownable {
    IPresaleFactory public PRESALE_FACTORY;
    IUniswapV2Locker public DAOLAUNCH_LOCKER;
    IUniswapV2Factory public UNI_FACTORY;

    constructor() {
        PRESALE_FACTORY = IPresaleFactory(
            0x132054493300a949fcf0CEB7180a40B92f0156E0
        );
        DAOLAUNCH_LOCKER = IUniswapV2Locker(
            0x43AD12Fa12F710A2EE34f27aac98A6A597b40940
        );
        UNI_FACTORY = IUniswapV2Factory(
            0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73
        );
    }

    /**
        Send in _token0 as the PRESALE token, _token1 as the BASE token (usually WETH) for the check to work. As anyone can create a pair, and send WETH to it while a presale is running, but no one should have access to the presale token. If they do and they send it to the pair, scewing the initial liquidity, this function will return true
    */
    function uniswapPairIsInitialised(address _token0, address _token1)
        public
        view
        returns (bool)
    {
        address pairAddress = UNI_FACTORY.getPair(_token0, _token1);
        if (pairAddress == address(0)) {
            return false;
        }
        uint256 balance = IERC20Custom(_token0).balanceOf(pairAddress);
        if (balance > 0) {
            return true;
        }
        return false;
    }

    function lockLiquidity(
        IERC20Custom _baseToken,
        IERC20Custom _saleToken,
        uint256 _baseAmount,
        uint256 _saleAmount,
        uint256 _unlock_date,
        address payable _withdrawer
    ) external {
        require(
            PRESALE_FACTORY.presaleIsRegistered(msg.sender),
            "PRESALE NOT REGISTERED"
        );
        address pair = UNI_FACTORY.getPair(
            address(_baseToken),
            address(_saleToken)
        );
        if (pair == address(0)) {
            UNI_FACTORY.createPair(address(_baseToken), address(_saleToken));
            pair = UNI_FACTORY.getPair(
                address(_baseToken),
                address(_saleToken)
            );
        }

        TransferHelper.safeTransferFrom(
            address(_baseToken),
            msg.sender,
            address(pair),
            _baseAmount
        );
        TransferHelper.safeTransferFrom(
            address(_saleToken),
            msg.sender,
            address(pair),
            _saleAmount
        );
        IUniswapV2Pair(pair).mint(address(this));
        uint256 totalLPTokensMinted = IUniswapV2Pair(pair).balanceOf(
            address(this)
        );
        require(totalLPTokensMinted != 0, "LP creation failed");

        TransferHelper.safeApprove(
            pair,
            address(DAOLAUNCH_LOCKER),
            totalLPTokensMinted
        );
        uint256 unlock_date = _unlock_date > 9999999999
            ? 9999999999
            : _unlock_date;
        DAOLAUNCH_LOCKER.lockLPToken(
            pair,
            totalLPTokensMinted,
            unlock_date,
            payable(address(0)),
            true,
            _withdrawer
        );
    }
}
