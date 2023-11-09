// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./SafeMath.sol";
import "./AggregatorV3Interface.sol";

contract Predicty {

    using SafeMath for *;

    enum Option {
        Bullish,
        Neutral,
        Bearish
    }

    enum MarketStatus {
        Live,
        InSettlement,
        Settled
    }

    struct Market {
        MarketStatus state;
        uint startTime;
        uint expireTime;
        uint neutralMinValue;
        uint neutralMaxValue;
        Option winningOption;
        uint settleTime;
        mapping(address => User) users;
        mapping(Option => uint) totalBets;
        uint totalPool;
    }

    struct User {
        bool claimedWinnings;
        mapping(Option => uint) amountStaked;
        bool claimedCreationReward;
        uint creationReward;
        bool claimedSettlementReward;
        uint settlementReward;
    }

    address payable public owner;
    address public oracle;
    AggregatorV3Interface internal priceFeed;
    bool public marketCreationPaused;
    uint constant commissionPercentage = 10;
    uint constant optionRangePercentage = 40;
    uint public commissionAmount;
    uint public marketCount;
    uint public marketDuration;

    mapping(uint => Market) public markets;

    event LogNewMarketCreated(uint indexed marketId, uint price);
    event LogBetPlaced(uint indexed marketId, address indexed user, Option option, uint value);
    event LogWinningsClaimed(uint indexed marketId, address indexed user, uint winnings);
    event LogResultPosted(uint indexed marketId, address indexed oracle, Option option);
    event LogCreationRewardClaimed(uint indexed marketId, address indexed user, uint creationReward);
    event LogSettlementRewardClaimed(uint indexed marketId, address indexed user, uint settlementReward);

    /**
    * @dev Modifier that only allows the authorized owner addresses to execute the function.
  */
    modifier onlyOwner() {
        require(msg.sender == owner, "=== Only the owner address can call this function ===");
        _;
    }

    /**
    * @dev Modifier that only allows a prediction market in the Live state to execute the function.
  * @param _marketId The id of the prediction market instance on which this modifier is called.
  */
    modifier onlyLive(uint _marketId) {
        require(getMarketStatus(_marketId) == MarketStatus.Live, "=== The prediction market must be live to call this function ===");
        _;
    }

    /**
    * @dev Modifier that only allows a prediction market in the InSettlement state to execute the function.
  * @param _marketId The id of the prediction market instance on which this modifier is called.
  */
    modifier onlyInSettlement(uint _marketId) {
        require(getMarketStatus(_marketId) == MarketStatus.InSettlement, "=== The prediction market must be in settlement to call this function ===");
        require(block.timestamp > getMarketSettleTime(_marketId), "=== The prediction market cannot be settled yet :( ===");
        _;
    }

    /**
    * @dev Modifier that only allows a prediction market in the Settled state to execute the function.
  * @param _marketId The id of the prediction market instance on which this modifier is called.
  */
    modifier onlySettled(uint _marketId) {
        require(getMarketStatus(_marketId) == MarketStatus.Settled, "=== The prediction market must be settled to execute this function ===");
        _;
    }

    /**
    * @dev Deploys the smart contract and fires up the first prediction market.
  * @param _oracle Sets the address of the oracle used used as pricefeed. Rinkeby ETH/USD price oracle = 0x8A753747A1Fa494EC906cE90E9f37563A8AF630e.
  * @param _duration Sets the duration of the prediction market cycles, i.e. duration = 1 hours will make sure that all prediction markets started by this smart contract will be Live for 1 hour and subsequently be InSetllement for 1 hour.
  */
    constructor(address _oracle, uint _duration) {
        oracle = _oracle;
        priceFeed = AggregatorV3Interface(oracle);
        owner = payable(msg.sender);
        marketDuration = _duration;
        marketCount = 0;
//        uint _price = getLatestPrice(); //returns latest ETH/USD in the following format: 40345000000 (8 decimals)
        uint _price = 40345000000;
        Market storage newMarket = markets[marketCount];
        newMarket.state = MarketStatus.Live;
        newMarket.startTime = (block.timestamp.div(3600)).mul(3600);
        newMarket.expireTime = newMarket.startTime.add(marketDuration);
        newMarket.neutralMinValue = _price.sub(_calculatePercentage(optionRangePercentage, _price, 10000));
        newMarket.neutralMaxValue = _price.add(_calculatePercentage(optionRangePercentage, _price, 10000));
        newMarket.settleTime = newMarket.startTime.add(marketDuration.mul(2));

        emit LogNewMarketCreated(marketCount, _price);
    }

    /**
    * @dev Places a bet amount on a specific bet option in the prediction market that is currently Live.
  * @param _option The specific bet option for which this function is called, i.e. Bullish, Neutral, or Bearish.
  */
    function placeBet(Option _option) external payable onlyLive(marketCount) {
        Market storage m = markets[marketCount];
        require(msg.value > 0,"=== Your bet should be greater than 0 ===");

        uint _predictionStake = msg.value;
        uint _commissionStake = _calculatePercentage(commissionPercentage, _predictionStake, 1000);
        commissionAmount = commissionAmount.add(_commissionStake);
        _predictionStake = _predictionStake.sub(_commissionStake);

        m.totalBets[_option] = m.totalBets[_option].add(_predictionStake);
        m.users[msg.sender].amountStaked[_option] = m.users[msg.sender].amountStaked[_option].add(_predictionStake);
        m.totalPool = m.totalPool.add(_predictionStake);

        emit LogBetPlaced(marketCount, msg.sender, _option, _predictionStake);
    }

    /**
    * @dev Settles the prediction market that is currently InSettlement, by calling the configured pricefeed oracle and incentivising the user address address for calling this function.
  */
    function settleMarket() external onlyInSettlement(marketCount) {
        Market storage m = markets[marketCount];

        (uint _price, ) = getSettlementPrice(m.settleTime);

        if(_price < m.neutralMinValue) {
            m.winningOption = Option.Bearish;
        } else if(_price > m.neutralMaxValue) {
            m.winningOption = Option.Bullish;
        } else {
            m.winningOption = Option.Neutral;
        }

        uint reward = _calculatePercentage(commissionPercentage, commissionAmount, 100);
        m.users[msg.sender].settlementReward = m.users[msg.sender].settlementReward.add(reward);
        commissionAmount = commissionAmount.sub(reward);

        emit LogResultPosted(marketCount, msg.sender, m.winningOption);
        m.state = MarketStatus.Settled;
    }

    /**
    * @dev Creates a new prediction market (after the previous one was settled), by calling the configured pricefeed oracle and incentivising the user address address for calling this function.
  * @return success Returns whether the market creation was successful.
  */
    function createNewMarket() public onlySettled(marketCount) returns(bool success) {
        require(!marketCreationPaused, "=== The owner has paused market creation ===");
        marketCount = marketCount.add(1);

        uint _price = getLatestPrice(); //returns latest ETH/USD in the following format: 40345000000 (8 decimals)

        Market storage newMarket = markets[marketCount];
        newMarket.state = MarketStatus.Live;
        newMarket.startTime = (block.timestamp.div(3600)).mul(3600);
        newMarket.expireTime = newMarket.startTime.add(marketDuration);
        newMarket.neutralMinValue = _price.sub(_calculatePercentage(optionRangePercentage, _price, 10000));
        newMarket.neutralMaxValue = _price.add(_calculatePercentage(optionRangePercentage, _price, 10000));
        newMarket.settleTime = newMarket.startTime.add(marketDuration.mul(2));

        uint reward = _calculatePercentage(commissionPercentage, commissionAmount, 100);
        newMarket.users[msg.sender].creationReward = newMarket.users[msg.sender].creationReward.add(reward);
        commissionAmount = commissionAmount.sub(reward);

        emit LogNewMarketCreated(marketCount, _price);

        return true;
    }

    /**
    * @dev Calculates the winnings for a specific user in the prediction market.
  * @param _marketId The id of the prediction market instance on which this function is called.
  * @param _user The specific user address for which this function is called.
  * @return winnings Returns the total amount that has been won by a specific user address in the prediction market.
  */
    function calculateWinnings(uint _marketId, address _user) public view returns(uint winnings) {
        Market storage m = markets[_marketId];
        uint winningBet = m.users[_user].amountStaked[m.winningOption];
        uint winningTotal = m.totalBets[m.winningOption];
        uint loserPool = m.totalPool.sub(winningTotal);
        winnings = loserPool.mul(winningBet).div(winningTotal);
        winnings = winnings.add(winningBet);

        return winnings;
    }

    /**
    * @dev Allows the calling user address to withdraw his/her winnings in the prediction market, after settlement.
  * @param _marketId The id of the prediction market instance on which this function is called.
  */
    function withdrawWinnings(uint _marketId) external onlySettled(_marketId) {
        Market storage m = markets[_marketId];
        require(m.users[msg.sender].claimedWinnings == false, "=== You already claimed your winnings for this market :( ===");

        uint winningBet = m.users[msg.sender].amountStaked[m.winningOption];
        require(winningBet > 0, "=== You have no bets on the winning option :( ===");

        uint winnings = calculateWinnings(_marketId, msg.sender);

        m.users[msg.sender].claimedWinnings = true;
        payable(msg.sender).transfer(winnings);

        emit LogWinningsClaimed(_marketId, msg.sender, winnings);
    }

    /**
    * @dev Allows the calling user address to withdraw his/her creation reward in the prediction market, after settlement.
  * @param _marketId The id of the prediction market instance on which this function is called.
  */
    function withdrawCreationReward(uint _marketId) external onlySettled(_marketId) {
        Market storage m = markets[_marketId];
        require(m.users[msg.sender].creationReward > 0, "=== You did not create this market ===");
        require(m.users[msg.sender].claimedCreationReward == false, "=== You already claimed your creation reward for this market :( ===");

        m.users[msg.sender].claimedCreationReward = true;

        payable(msg.sender).transfer(m.users[msg.sender].creationReward);

        emit LogCreationRewardClaimed(_marketId, msg.sender, m.users[msg.sender].creationReward);
    }

    /**
    * @dev Allows the calling user address to withdraw his/her settlement reward in the prediction market, after settlement.
  * @param _marketId The id of the prediction market instance on which this function is called.
  */
    function withdrawSettlementReward(uint _marketId) external onlySettled(_marketId) {
        Market storage m = markets[_marketId];
        require(m.users[msg.sender].settlementReward > 0, "=== You did not settle this market ===");
        require(m.users[msg.sender].claimedSettlementReward == false, "=== You already claimed your settlement reward for this market :( ===");

        m.users[msg.sender].claimedSettlementReward = true;

        payable(msg.sender).transfer(m.users[msg.sender].settlementReward);

        emit LogSettlementRewardClaimed(_marketId, msg.sender, m.users[msg.sender].settlementReward);
    }

    /**
    * @dev Gets the latest/current asset price (e.g. ETH/USD) from the configured pricefeed oracle.
  * @return latestPrice Returns the latest/current asset price (e.g. ETH/USD) from the configured pricefeed oracle.
  */
    function getLatestPrice() public view returns (uint latestPrice) {
        (uint80 roundId, int price, uint startedAt, uint timeStamp, uint80 answeredInRound) = priceFeed.latestRoundData();
        // If the round is not complete yet, timestamp is 0
        require(timeStamp > 0, "Round not complete");
        return uint256(price);
    }

    /**
    * @dev Gets the historical asset price (e.g. ETH/USD) at prediction market settlement time from the configured pricefeed oracle.
  * @param _settleTime The prediction market settlement timestamp, for which an historical asset price should be returned.
  * @return settlementPrice Returns the historical asset price (e.g. ETH/USD) at prediction market settlement time from the configured pricefeed oracle.
  * @return roundId Returns the matching roundId from the configured pricefeed oracle, for the historical asset price.
  */
    function getSettlementPrice(uint _settleTime) public view returns(uint settlementPrice, uint roundId) {
        uint80 currentRoundId;
        int currentRoundPrice;
        uint currentRoundTimeStamp;
        (currentRoundId, currentRoundPrice, , currentRoundTimeStamp, ) = priceFeed.latestRoundData();
        while(currentRoundTimeStamp > _settleTime) {
            currentRoundId--;
            (currentRoundId, currentRoundPrice, , currentRoundTimeStamp, ) = priceFeed.getRoundData(currentRoundId);
            if(currentRoundTimeStamp <= _settleTime) {
                break;
            }
        }
        return (uint(currentRoundPrice), currentRoundId);
    }

    /**
    * @dev Gets the status of the prediction market.
  * @param _marketId The id of the prediction market instance on which this function is called.
  * @return status Returns the updated status of the prediction market.
  */
    function getMarketStatus(uint _marketId) public view returns(MarketStatus status){
        Market storage m = markets[_marketId];
        if(m.state == MarketStatus.Live && block.timestamp > m.expireTime) {
            return MarketStatus.InSettlement;
        } else {
            return m.state;
        }
    }

    /**
    * @dev Gets the prediction market start timestamp (as seconds since unix epoch).
  * @param _marketId The id of the prediction market instance on which this function is called.
  * @return startTime Returns the start time of the prediction market.
  */
    function getMarketStartTime(uint _marketId) public view returns(uint startTime) {
        Market storage m = markets[_marketId];
        return m.startTime;
    }

    /**
    * @dev Gets the prediction market expire timestamp (as seconds since unix epoch). After the expiry of the prediction market users can no longer place bets.
  * @param _marketId The id of the prediction market instance on which this function is called.
  * @return expireTime Returns the expire time of the prediction market.
  */
    function getMarketExpireTime(uint _marketId) public view returns(uint expireTime) {
        Market storage m = markets[_marketId];
        return m.expireTime;
    }

    /**
    * @dev Gets the prediction market settlement timestamp (as seconds since unix epoch). As of the settlement timestamp, the pricefeed oracle can be called to settle the prediction market.
  * @param _marketId The id of the prediction market instance on which this function is called.
  * @return settleTime Returns the settlement time of the prediction market.
  */
    function getMarketSettleTime(uint _marketId) public view returns(uint settleTime) {
        Market storage m = markets[_marketId];
        return m.settleTime;
    }

    /**
    * @dev Gets the prediction market neutral minimum price value. The neutral minimum price value forms the lower bound of the Neutral betting option.
  * @param _marketId The id of the prediction market instance on which this function is called.
  * @return minValue Returns the neutral minimum price value of the prediction market.
  */
    function getNeutralMinValue(uint _marketId) public view returns(uint minValue) {
        Market storage m = markets[_marketId];
        return m.neutralMinValue;
    }

    /**
    * @dev Gets the prediction market neutral maximum price value. The neutral maximum price value forms the upper bound of the Neutral betting option.
  * @param _marketId The id of the prediction market instance on which this function is called.
  * @return maxValue Returns the neutral maximum price value of the prediction market.
  */
    function getNeutralMaxValue(uint _marketId) public view returns(uint maxValue) {
        Market storage m = markets[_marketId];
        return m.neutralMaxValue;
    }

    /**
    * @dev Gets the winning option after prediction market settlement.
  * @param _marketId The id of the prediction market instance on which this function is called.
  * @return winner Returns the winning option, i.e. Bullish, Neutral, or Bearish.
  */
    function getWinningOption(uint _marketId) public view returns(Option winner) {
        Market storage m = markets[_marketId];
        return m.winningOption;
    }

    /**
    * @dev Gets the total amount that has been staked on all bet options together in the prediction market.
  * @param _marketId The id of the prediction market instance on which this function is called.
  * @return totalPool Returns the total amount that has been staked on all bet options together in the prediction market.
  */
    function getMarketTotalPool(uint _marketId) public view returns(uint totalPool) {
        Market storage m = markets[_marketId];
        return m.totalPool;
    }

    /**
    * @dev Gets the total amount that has been staked on a specific bet option in the prediction market.
  * @param _marketId The id of the prediction market instance on which this function is called.
  * @param _option The specific bet option for which this function is called, i.e. Bullish, Neutral, or Bearish.
  * @return totalBets Returns the total amount that has been staked on a specific bet option in the prediction market.
  */
    function getMarketTotalBets(uint _marketId, Option _option) public view returns(uint totalBets) {
        Market storage m = markets[_marketId];
        return m.totalBets[_option];
    }

    /**
    * @dev Gets a boolean value returning whether a specific user address has already claimed his/her winnings in the predition market.
  * @param _marketId The id of the prediction market instance on which this function is called.
  * @param _user The specific user address for which this function is called.
  * @return claimed Returns whether a specific user address has already claimed his/her winnings in the predition market.
  */
    function getUserClaimedWinnings(uint _marketId, address _user) public view returns(bool claimed) {
        Market storage m = markets[_marketId];
        return m.users[_user].claimedWinnings;
    }

    /**
    * @dev Gets the total amount that has been staked by a specific user address on a specific bet option in the prediction market.
  * @param _marketId The id of the prediction market instance on which this function is called.
  * @param _user The specific user address for which this function is called.
  * @param _option The specific bet option for which this function is called, i.e. Bullish, Neutral, or Bearish.
  * @return amountStaked Returns the total amount that has been staked by a specific user address on a specific bet option in the prediction market.
  */
    function getUserAmountStaked(uint _marketId, address _user, Option _option) public view returns(uint amountStaked) {
        Market storage m = markets[_marketId];
        return m.users[_user].amountStaked[_option];
    }

    /**
    * @dev Gets a boolean value returning whether a specific user address has already claimed his/her reward for creating the predition market.
  * @param _marketId The id of the prediction market instance on which this function is called.
  * @param _user The specific user address for which this function is called.
  * @return claimed Returns whether a specific user address has already claimed his/her reward for creating the predition market.
  */
    function getUserClaimedCreationReward(uint _marketId, address _user) public view returns(bool claimed) {
        Market storage m = markets[_marketId];
        return m.users[_user].claimedCreationReward;
    }

    /**
    * @dev Gets the reward amount that has been awarded to a specific user address for creating the prediction market.
  * @param _marketId The id of the prediction market instance on which this function is called.
  * @param _user The specific user address for which this function is called.
  * @return reward Returns the reward amount that has been awarded to a specific user address for creating the prediction market.
  */
    function getUserCreationReward(uint _marketId, address _user) public view returns(uint reward) {
        Market storage m = markets[_marketId];
        return m.users[_user].creationReward;
    }

    /**
    * @dev Gets a boolean value returning whether a specific user address has already claimed his/her reward for settling the predition market.
  * @param _marketId The id of the prediction market instance on which this function is called.
  * @param _user The specific user address for which this function is called.
  * @return claimed Returns whether a specific user address has already claimed his/her reward for settling the predition market.
  */
    function getUserClaimedSettlementReward(uint _marketId, address _user) public view returns(bool claimed) {
        Market storage m = markets[_marketId];
        return m.users[_user].claimedSettlementReward;
    }

    /**
    * @dev Gets the reward amount that has been awarded to a specific user address for settling the prediction market.
  * @param _marketId The id of the prediction market instance on which this function is called.
  * @param _user The specific user address for which this function is called.
  * @return reward Returns the reward amount that has been awarded to a specific user address for settling the prediction market.
  */
    function getUserSettlementReward(uint _marketId, address _user) public view returns(uint reward) {
        Market storage m = markets[_marketId];
        return m.users[_user].settlementReward;
    }

    /**
    * @dev Gets the current balance of the smart contract.
  * @return balance Returns the current balance of the smart contract.
  */
    function getContractBalance() public view returns(uint balance) {
        return address(this).balance;
    }

    /**
    * @dev Helper function to get the percentage value for a given input value.
  * @param _percent The percentage value.
  * @param _value The input value.
  * @param _divisor The divisor value.
  * @return The percentage value for a given input value.
  */
    function _calculatePercentage(uint256 _percent, uint256 _value, uint256 _divisor) internal pure returns(uint256) {
        return _percent.mul(_value).div(_divisor);
    }

    /**
    * @dev Updates the address of the pricefeed oracle (e.g. the ChainLink ETH/USD pricefeed oracle).
  * @param _oracle The new address of the pricefeed oracle.
  */
    function updateOracleAddress(address _oracle) external onlyOwner {
        oracle = _oracle;
    }

    /**
    * @dev Updates the flag to pause market creation, in case of issues.
  */
    function pauseMarketCreation() external onlyOwner {
        require(!marketCreationPaused);
        marketCreationPaused = true;
    }

    /**
    * @dev Updates the flag to resume market creation, when issues are solved.
  */
    function resumeMarketCreation() external onlyOwner {
        require(marketCreationPaused);
        marketCreationPaused = false;
    }

    /**
    * @dev Destroys the smart contract instance and sends all remaining Ether stored in the smart contract to the owner address.
  */
    function destroy() public onlyOwner {
        selfdestruct(owner);
    }

    fallback () external payable {
        revert("=== Please use the dedicated functions to place bets and/or transfer ether into this smart contract ===");
    }

    receive() external payable {
        revert("=== Please use the dedicated functions to place bets and/or transfer ether into this smart contract ===");
    }

}
