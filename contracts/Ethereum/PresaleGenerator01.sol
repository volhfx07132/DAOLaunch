// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../Unitls/Ownable.sol";
import "../Comment/IERC20Custom.sol";
import "./Presale01.sol";
import "../Comment/TransferHelper.sol";
import "../Comment/PresaleHelper.sol";
import "../Comment/IPresaleFactory.sol";
import "../Comment/IUniswapV2Locker.sol";
import "../Unitls/EnumerableSet.sol";

contract PresaleGenerator01 is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

        IPresaleFactory public PRESALE_FACTORY;
        IPresaleSettings public PRESALE_SETTINGS;
    EnumerableSet.AddressSet private admins;

    struct PresaleParams {
        uint256 amount;
        uint256 tokenPrice;
        uint256 maxSpendPerBuyer;
        uint256 minSpendPerBuyer;
        uint256 hardcap;
        uint256 softcap;
        uint256 liquidityPercent;
        uint256 listingRate; // sale token listing price on uniswap
        uint256 starttime;
        uint256 endtime;
        uint256 lockPeriod;
        uint256 uniswapListingTime;
        // if set time for user withdraw at C : use same data in uint_params[11], otherwise set new Date for it
        uint256 firstDistributionType;
        uint256 firstUnlockRate;
        uint256 distributionInterval;
        uint256 unlockRateEachTime;
        uint256 maxPeriod;
    }

    modifier onlyAdmin() {
        require(admins.contains(_msgSender()), "NOT ADMIN");
        _;
    }

    constructor() {
        PRESALE_FACTORY = IPresaleFactory(
            0x132054493300a949fcf0CEB7180a40B92f0156E0
        );
        PRESALE_SETTINGS = IPresaleSettings(
            0xcFb2Cb97028c4e2fe6b868D685C00ab96e6Ec370
        );

        admins.add(0x96B18a23114003902c7ee6b998037ACbD1B4332b);
        admins.add(0xAC085Ab96C4170c326Ff87Cccfb2Fb93B9DC4bEf);
        admins.add(0x75d69272c5A9d6FCeC0D68c547776C7195f73feA);
    }

    /**
     * @notice Creates a new Presale contract and registers it in the PresaleFactory.sol.
     */
    function createPresale(
        address payable _presaleOwner,
        IERC20Custom _presaleToken,
        IERC20Custom _baseToken,
        bool is_white_list,
        uint256[12] memory uint_params,
        address payable _caller,
        uint256[5] memory _vestingPeriod,
        uint8 _addLP // 0: smart contract, 1: only distribution, 2: off-chain
    ) public payable {
        PresaleParams memory params;
        params.amount = uint_params[0];
        params.tokenPrice = uint_params[1];
        params.maxSpendPerBuyer = uint_params[2];
        params.minSpendPerBuyer = uint_params[3];
        params.hardcap = uint_params[4];
        params.softcap = uint_params[5];
        params.liquidityPercent = uint_params[6];
        params.listingRate = uint_params[7];
        params.starttime = uint_params[8];
        params.endtime = uint_params[9];
        params.lockPeriod = uint_params[10];
        params.uniswapListingTime = uint_params[11];

        require(params.uniswapListingTime > params.endtime);
        // Charge ETH fee for contract creation
        require(
            msg.value == PRESALE_SETTINGS.getEthCreationFee(),
            "FEE NOT MET"
        );

        // require(params.amount >= 10000, "MIN DIVIS"); // minimum divisibility
        require(params.endtime > params.starttime, "INVALID BLOCK TIME");
        require(params.tokenPrice * params.hardcap > 0, "INVALID PARAMS"); // ensure no overflow for future calculations
        require(
            // params.liquidityPercent >= 300 &&
            params.liquidityPercent <= 1000,
            "MIN LIQUIDITY"
        ); // 30% minimum liquidity lock
        uint256 tokensRequiredForPresale = PresaleHelper
            .calculateAmountRequired(
                params.amount,
                params.tokenPrice,
                params.listingRate,
                params.liquidityPercent,
                PRESALE_SETTINGS.getBaseFee()
            );

        Presale01 newPresale = (new Presale01){value: msg.value}(address(this), admins.values());

        TransferHelper.safeTransferFrom(
            address(_presaleToken),
            address(msg.sender),
            address(newPresale),
            tokensRequiredForPresale
        );
        uint256[11] memory tmpData = [
            uint_params[0],
            uint_params[1],
            uint_params[2],
            uint_params[3],
            uint_params[4],
            uint_params[5],
            uint_params[6],
            uint_params[7],
            uint_params[8],
            uint_params[9],
            uint_params[10]
        ];
        newPresale.init1(_presaleOwner, tmpData);
        uint256[3] memory tmpData2 = [
            PRESALE_SETTINGS.getBaseFee(),
            PRESALE_SETTINGS.getTokenFee(),
            uint_params[11]
        ];
        newPresale.init2(
            _baseToken,
            _presaleToken,
            tmpData2,
            PRESALE_SETTINGS.getEthAddress(),
            PRESALE_SETTINGS.getTokenAddress()
        );

        newPresale.init3(is_white_list, _caller, _vestingPeriod, _addLP);
        PRESALE_FACTORY.registerPresale(address(newPresale));
    }

    function updateAdmin(address _adminAddr, bool _flag) external onlyAdmin {
        require(_adminAddr != address(0), "INVALID ADDRESS");
        if (_flag) {
            // add
            admins.add(_adminAddr);
        } else {
            // remove
            admins.remove(_adminAddr);
        }
    }

    function getAdmins() external view returns (address[] memory) {
        return admins.values();
    }
}
