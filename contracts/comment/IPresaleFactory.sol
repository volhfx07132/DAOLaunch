pragma solidity ^0.8.0;

interface IpresaleFactory{
    function registerPresale(address _presaleAddress) external;

    function presaleIsRegistered(address _presaleAddress) external view returns (bool);
}