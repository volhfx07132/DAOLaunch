// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

library PresaleHelper {
    function calculateAmountRequired(
        uint256 _amount,
        uint256 _tokenPrice,
        uint256 _listingRate,
        uint256 _liquidityPercent,
        uint256 _tokenFee
    ) public pure returns (uint256) {
        // uint256 listingRatePercent = _listingRate * 1000 / _tokenPrice;
        // uint256 DAOLaunchTokenFee = _amount * _tokenFee / 1000;
        // uint256 amountMinusFee = _amount - DAOLaunchTokenFee;
        // uint256 liquidityRequired = amountMinusFee * _liquidityPercent * listingRatePercent / 1000000;
        uint256 liquidityRequired = (_amount *
            (1000 - _tokenFee) *
            _liquidityPercent *
            _listingRate) /
            _tokenPrice /
            1000000;
        uint256 tokensRequiredForPresale = _amount + liquidityRequired;
        return tokensRequiredForPresale;
    }
}
