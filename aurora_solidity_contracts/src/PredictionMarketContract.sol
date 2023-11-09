// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract PredictionMarketContract {
    struct Bet {
        address bettor;
        uint256 amount;
        string prediction;
    }

    struct Market {
        uint256 id;
        string description;
        string[] outcomes;
        Bet[] bets;
        bool resolved;
        string winningOutcome;
        uint256 totalStaked;
        address creator;
    }

    mapping(uint256 => Market) public markets;
    uint256 public marketCount;

    // Events
    event MarketCreated(uint256 id, string description);
    event BetPlaced(uint256 marketId, address bettor, uint256 amount, string prediction);
    event MarketSettled(uint256 marketId, string winningOutcome);
    event FundsWithdrawn(uint256 marketId, address creator, uint256 amount);

    // Modifiers
    modifier onlyCreator(uint256 marketId) {
        require(markets[marketId].creator == msg.sender, "Only the creator can call this");
        _;
    }

    modifier marketExists(uint256 marketId) {
        require(markets[marketId].creator != address(0), "Market does not exist");
        _;
    }

    modifier marketNotResolved(uint256 marketId) {
        require(!markets[marketId].resolved, "Market already resolved");
        _;
    }

    constructor() {
        marketCount = 0;
    }

    function createMarket(string memory description, string[] memory outcomes) public {
        markets[marketCount] = Market(marketCount, description, outcomes, new Bet[](0), false, "", 0, msg.sender);
        emit MarketCreated(marketCount, description);
        marketCount++;
    }

    function placeBet(uint256 marketId, string memory prediction) public payable marketExists(marketId) marketNotResolved(marketId) {
        Bet memory bet = Bet(msg.sender, msg.value, prediction);
        markets[marketId].bets.push(bet);
        markets[marketId].totalStaked += msg.value;
        emit BetPlaced(marketId, msg.sender, msg.value, prediction);
    }

    function settleMarket(uint256 marketId, string memory winningOutcome) public onlyCreator(marketId) marketNotResolved(marketId) {
        Market storage market = markets[marketId];
        uint256 totalStakedOnWinner = 0;
        for(uint i = 0; i < market.bets.length; i++) {
            if (keccak256(bytes(market.bets[i].prediction)) == keccak256(bytes(winningOutcome))) {
                totalStakedOnWinner += market.bets[i].amount;
            }
        }

        if (totalStakedOnWinner > 0) {
            for(uint i = 0; i < market.bets.length; i++) {
                Bet storage bet = market.bets[i];
                if (keccak256(bytes(bet.prediction)) == keccak256(bytes(winningOutcome))) {
                    uint256 payout = (bet.amount * market.totalStaked) / totalStakedOnWinner;
                    payable(bet.bettor).transfer(payout);
                }
            }
        }

        market.resolved = true;
        market.winningOutcome = winningOutcome;

        // mint NFT
        
        emit MarketSettled(marketId, winningOutcome);
    }

    function withdrawFunds(uint256 marketId) public onlyCreator(marketId) {
        Market storage market = markets[marketId];
        require(market.resolved, "Market is not resolved yet");

        uint256 fundsToWithdraw = market.totalStaked;
        market.totalStaked = 0;
        payable(market.creator).transfer(fundsToWithdraw);
        emit FundsWithdrawn(marketId, market.creator, fundsToWithdraw);
    }

    function getTotalStaked(uint256 marketId) public view marketExists(marketId) returns (uint256) {
        return markets[marketId].totalStaked;
    }

    // Additional functions like getMarkets can be implemented based on specific requirements
}