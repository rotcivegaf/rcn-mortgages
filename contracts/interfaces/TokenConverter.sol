pragma solidity ^0.4.19;

import "./../interfaces/Token.sol";

contract TokenConverter {
    function getReturn(Token _fromToken, Token _toToken, uint256 _amount) public view returns (uint256 amount);
    function convert(Token _fromToken, Token _toToken, uint256 _amount, uint256 _minReturn) public returns (uint256 amount);
}