// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DaolaunchTokenMetrics is Ownable {

    struct LockingPeriod {
        uint256 lockPercent;
        uint256 firstDistributionType;
        uint256 firstUnlockRate;
        uint256 distributionInterval;
        uint256 unlockRateEachTime;
        uint256 maxPeriod;
        uint256 totalWithdraw;
        uint256 lastWithdraw;
        address distributionAddress;
    }

    struct TokenData {
        uint256 currentDataId;
        uint256 currentPercentLock;
        uint256 originalBalance;
        address originAddress;
        mapping(uint256 => uint256) lockData;
    }
    mapping(address => TokenData) public tokenInfo;
    mapping(address => mapping(uint256 => LockingPeriod)) public lockingPeriodInfo; //check by data id

    constructor() {}
    
    event UpdateTokenMetrics(address tokenAddress, LockingPeriod[] indexed lData);
    event ClaimedId(address tokenAddress, uint256 indexed dataId, uint256 indexed amount);

    //sender must approve to contract with correct amount before call this function
    function updateTokenMetrics(address tokenAddress, LockingPeriod[] memory lData) public {
        //first time call
        if(tokenInfo[tokenAddress].currentDataId == 0){
            tokenInfo[tokenAddress].originAddress = _msgSender();
            tokenInfo[tokenAddress].originalBalance = IERC20(tokenAddress).totalSupply();
        }
        require(lData.length > 0, "Must lock data");
        uint256 _totalLock;
         uint256 _tmpDataId = tokenInfo[tokenAddress].currentDataId;

        for (uint256 index = 0; index < lData.length; index++) {
            _totalLock = _totalLock + lData[index].lockPercent;
            tokenInfo[tokenAddress].lockData[_tmpDataId] = lData[index].lockPercent;
            lockingPeriodInfo[tokenAddress][_tmpDataId] = LockingPeriod (
                lData[index].lockPercent,
                lData[index].firstDistributionType,
                lData[index].firstUnlockRate,
                lData[index].distributionInterval,
                lData[index].unlockRateEachTime,
                lData[index].maxPeriod,
                0,0,
                lData[index].distributionAddress
            );
            _tmpDataId++;
        }
        require(_totalLock + tokenInfo[tokenAddress].currentPercentLock <= 1000, "Over 100% lock");
        tokenInfo[tokenAddress].currentDataId = _tmpDataId;
        uint256 currentLockAmount = _totalLock * tokenInfo[tokenAddress].originalBalance / 1000;
        IERC20(tokenAddress).transferFrom(_msgSender(), address(this), currentLockAmount);
        tokenInfo[tokenAddress].currentPercentLock += _totalLock;
        emit UpdateTokenMetrics(tokenAddress, lData);
    }
    
    function claimForId(address tokenAddress, uint256 dataId) public {
        require(tokenInfo[tokenAddress].originAddress == _msgSender(), "Only origin owner can claim");
        require(block.timestamp >= lockingPeriodInfo[tokenAddress][dataId].firstDistributionType, "Not now");
        uint256 lockPercent = tokenInfo[tokenAddress].lockData[dataId];
        uint256 lockAmount = lockPercent * tokenInfo[tokenAddress].originalBalance / 1000;

        uint256 rateWithdrawAfter;
        uint256 currentTime;
        LockingPeriod storage tmpLockPeriodData = lockingPeriodInfo[tokenAddress][dataId];

        if (block.timestamp > tmpLockPeriodData.maxPeriod) {
            currentTime = tmpLockPeriodData.maxPeriod;
        } else {
            currentTime = block.timestamp;
        }

        if (tmpLockPeriodData.firstUnlockRate == 1000) {
            require(tmpLockPeriodData.totalWithdraw != lockAmount, "Already withdraw all");
            rateWithdrawAfter = 1000;
        } else {
            uint256 spentCycles = (currentTime - tmpLockPeriodData.firstDistributionType) / tmpLockPeriodData.distributionInterval; // (m' - m0)/k

            if (tmpLockPeriodData.lastWithdraw == 0) {
                rateWithdrawAfter = tmpLockPeriodData.firstUnlockRate + spentCycles  * tmpLockPeriodData.unlockRateEachTime; //x + spentCycles*y
            } else {
                uint256 lastSpentCycles = (tmpLockPeriodData.lastWithdraw - tmpLockPeriodData.firstDistributionType) / tmpLockPeriodData.distributionInterval; // (LD - M0)/k
                rateWithdrawAfter = (spentCycles - lastSpentCycles) *  tmpLockPeriodData.unlockRateEachTime;//(spentCycles - lastSpentCycles)*y
                require(rateWithdrawAfter > 0, "INVALID MOMENT"); // SUCCESS
            }
        }
        tmpLockPeriodData.lastWithdraw = currentTime;
        uint256 amountWithdraw = lockAmount * rateWithdrawAfter / 1000;

        if (tmpLockPeriodData.totalWithdraw + amountWithdraw > lockAmount) {
            amountWithdraw = lockAmount - tmpLockPeriodData.totalWithdraw;
        }

        tmpLockPeriodData.totalWithdraw += amountWithdraw; // update total token withdraw
        IERC20(tokenAddress).transfer(tmpLockPeriodData.distributionAddress, amountWithdraw);
        emit ClaimedId(tokenAddress, dataId, amountWithdraw);
    }
}
