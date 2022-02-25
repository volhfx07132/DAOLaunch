// SPDX-License-Identifier: UNLICENSED


pragma solidity ^0.8.0;

interface IPresaleSettings {
    function getMaxPresaleLength() external view returns (uint256);

    function getBaseFee() external view returns (uint256);

    function getTokenFee() external view returns (uint256);

    function getEthAddress() external view returns (address payable);

    function getTokenAddress() external view returns (address payable);

    function getEthCreationFee() external view returns (uint256);
}
