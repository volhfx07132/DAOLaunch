pragma solidity >=0.7.0 < 0.9.0;
 
abstract contract Context{
    function _msgSender() internal view virtual returns(address){
        return msg.sender;
    }

    function _msgData() internal view virtual returns(uint256){
        return msg.value;
    }
}