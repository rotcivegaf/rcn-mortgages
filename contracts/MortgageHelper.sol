pragma solidity ^0.4.19;

import "./interfaces/Token.sol";
import "./interfaces/TokenConverter.sol";
// import "./MortgageManager.sol";
// import "./ConverterRamp.sol";
import "./utils/LrpSafeMath.sol";
import "./utils/Ownable.sol";

contract LandMarket {
    struct Auction {
        // Auction ID
        bytes32 id;
        // Owner of the NFT
        address seller;
        // Price (in wei) for the published item
        uint256 price;
        // Time when this sale ends
        uint256 expiresAt;
    }

    mapping (uint256 => Auction) public auctionByAssetId;
}

interface ConverterRamp {

}

interface Engine {

}

contract NanoLoanEngine is Engine {
    function createLoan(address _oracleContract, address _borrower, bytes32 _currency, uint256 _amount, uint256 _interestRate,
        uint256 _interestRatePunitory, uint256 _duesIn, uint256 _cancelableAt, uint256 _expirationRequest, string _metadata) public returns (uint256);
    function registerApprove(bytes32 identifier, uint8 v, bytes32 r, bytes32 s) public returns (bool);
    function getAmount(uint index) public view returns (uint256);
    function getIdentifier(uint index) public view returns (bytes32);
}

interface MortgageManager {
    function requestMortgageId(Engine, uint256, uint256, uint256, TokenConverter) public returns (uint256);
}

contract MortgageHelper is Ownable {
    using LrpSafeMath for uint256;

    MortgageManager public mortgageManager;
    NanoLoanEngine public nanoLoanEngine;
    Token public rcn;
    Token public mana;
    LandMarket public landMarket;
    TokenConverter public tokenConverter;
    ConverterRamp public converterRamp;

    address public manaOracle;
    uint256 public requiredTotal = 110;

    uint256 public rebuyThreshold = 0.001 ether;
    uint256 public marginSpend = 100;

    bytes32 public constant MANA_CURRENCY = 0x4d414e4100000000000000000000000000000000000000000000000000000000;

    event NewMortgage(address borrower, uint256 loanId, uint256 landId, uint256 mortgageId);

    function MortgageHelper(
        MortgageManager _mortgageManager,
        NanoLoanEngine _nanoLoanEngine,
        Token _rcn,
        Token _mana,
        LandMarket _landMarket,
        address _manaOracle,
        TokenConverter _tokenConverter,
        ConverterRamp _converterRamp
    ) public {
        mortgageManager = _mortgageManager;
        nanoLoanEngine = _nanoLoanEngine;
        rcn = _rcn;
        mana = _mana;
        landMarket = _landMarket;
        manaOracle = _manaOracle;
        tokenConverter = _tokenConverter;
        converterRamp = _converterRamp;
    }

    function createLoan(uint256[6] memory params, string metadata) internal returns (uint256) {
        return nanoLoanEngine.createLoan(
            manaOracle,
            msg.sender,
            MANA_CURRENCY,
            params[0],
            params[1],
            params[2],
            params[3],
            params[4],
            params[5],
            metadata
        );
    }

    function setConverterRamp(ConverterRamp _converterRamp) public onlyOwner returns (bool) {
        converterRamp = _converterRamp;
        return true;
    }

    function setRebuyThreshold(uint256 _rebuyThreshold) public onlyOwner returns (bool) {
        rebuyThreshold = _rebuyThreshold;
        return true;
    }

    function setMarginSpend(uint256 _marginSpend) public onlyOwner returns (bool) {
        marginSpend = _marginSpend;
        return true;
    }

    function setTokenConverter(TokenConverter _tokenConverter) public onlyOwner returns (bool) {
        tokenConverter = _tokenConverter;
        return true;
    }

    function requestMortgage(uint256[6] memory loanParams, string metadata, uint256 landId, uint8 v, bytes32 r, bytes32 s) public returns (uint256) {
        uint256 loanId = createLoan(loanParams, metadata);
        require(nanoLoanEngine.registerApprove(nanoLoanEngine.getIdentifier(loanId), v, r, s));

        uint256 landCost;
        (, , landCost, ) = landMarket.auctionByAssetId(landId);

        uint256 requiredDeposit = ((landCost * requiredTotal) / 100) - nanoLoanEngine.getAmount(loanId);
        
        require(mana.transferFrom(msg.sender, this, requiredDeposit));
        require(mana.approve(mortgageManager, requiredDeposit));

        uint256 mortgageId = mortgageManager.requestMortgageId(Engine(nanoLoanEngine), loanId, requiredDeposit, landId, tokenConverter);
        NewMortgage(msg.sender, loanId, landId, mortgageId);
        
        return mortgageId;
    }

    function pay(address engine, uint256 loan, uint256 amount) public returns (bool) {
        bytes32[4] memory loanParams = [
            bytes32(engine),
            bytes32(loan),
            bytes32(amount),
            bytes32(msg.sender)
        ];

        uint256[3] memory converterParams = [
            marginSpend,
            amount.safeMult(uint256(100000).safeAdd(marginSpend)) / 100000,
            rebuyThreshold
        ];

        require(address(converterRamp).delegatecall(
            bytes4(0x86ee863d),
            address(tokenConverter),
            address(mana),
            loanParams,
            0x140,
            converterParams,
            0x0
        ));
    }
}