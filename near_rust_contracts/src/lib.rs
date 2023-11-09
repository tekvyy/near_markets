// Find all our documentation at https://docs.near.org
use near_sdk::borsh::{self, BorshDeserialize, BorshSerialize};
use near_sdk::env::log_str;
use near_sdk::near_bindgen;
use near_sdk::{env, AccountId, Balance, PanicOnDefault, Promise};
use near_sdk::collections::LookupMap;

// Define the structure of a bet
#[derive(BorshDeserialize, BorshSerialize)]
pub struct Bet {
    pub bettor: AccountId,
    pub amount: Balance,
    pub prediction: String,
}

// Define the structure of a market
#[derive(BorshDeserialize, BorshSerialize)]
pub struct Market {
    pub id: u64,
    pub description: String,
    pub outcomes: Vec<String>,
    pub bets: Vec<Bet>,
    pub resolved: bool,
    pub winning_outcome: Option<String>,
    pub total_staked: Balance,
    pub creator: AccountId,
}

// Define the structure of your prediction market contract
#[near_bindgen]
#[derive(BorshDeserialize, BorshSerialize, PanicOnDefault)]
pub struct PredictionMarketContract {
    markets: LookupMap<u64, Market>,
    market_count: u64,
}


#[near_bindgen]
impl PredictionMarketContract {

    // Initializes the contract with the given context
    #[init]
    pub fn new() -> Self {
        assert!(!env::state_exists(), "Already initialized");
        Self {
            markets: LookupMap::new(b"m"),
            market_count: 0,
        }
    }

    // Creates a new prediction market
    pub fn create_market(&mut self, description: String, outcomes: Vec<String>) {
        let market = Market {
            id: self.market_count,
            description,
            outcomes,
            bets: Vec::new(),
            resolved: false,
            winning_outcome: None,
            creator:env::predecessor_account_id(),
            total_staked:0,
        };
        self.markets.insert(&self.market_count, &market);
        self.market_count += 1;
    }

    // Allows users to place a bet on a market
    #[payable]
    pub fn place_bet(&mut self, market_id: u64, prediction: String) {
        let mut market = self.markets.get(&market_id).expect("Market not found");
        assert!(!market.resolved, "Market already resolved");

        let bet = Bet {
            bettor: env::predecessor_account_id(),
            amount: env::attached_deposit(),
            prediction,
        };

        market.bets.push(bet);
        self.markets.insert(&market_id, &market);
    }

    // Settles a market and distributes payouts based on the outcome
    pub fn settle_market(&mut self, market_id: u64, winning_outcome: String) {
        let mut market = self.markets.get(&market_id).expect("Market not found");
        assert!(!market.resolved, "Market already resolved");

        market.winning_outcome = Some(winning_outcome.clone());
        market.resolved = true;

        let total_staked_on_winner = market.bets.iter()
            .filter(|bet| bet.prediction == winning_outcome)
            .map(|bet| bet.amount)
            .sum::<Balance>();

        for bet in market.bets.iter() {
            if bet.prediction == winning_outcome {
                // Calculate the user's share of the total winning bets
                let share = bet.amount as f64 / total_staked_on_winner as f64;
                // Calculate the user's payout (user's share of the total stakes)
                let payout = (market.total_staked as f64 * share) as Balance;
                Promise::new(bet.bettor.clone()).transfer(payout);
            }
        }

        self.markets.insert(&market_id, &market);
    }

    // Allows the market creator to withdraw funds from resolved markets
    pub fn withdraw_funds(&mut self, market_id: u64) {
        let mut market = self.markets.get(&market_id).expect("Market not found");
        assert!(market.resolved, "Market is not resolved yet");
        assert!(env::predecessor_account_id() == market.creator, "Only the creator can withdraw funds");

        // Calculate the remaining funds after payouts
        let funds_to_withdraw = market.total_staked; // Simplified for illustration purposes
        market.total_staked = 0;

        Promise::new(env::predecessor_account_id()).transfer(funds_to_withdraw);
        self.markets.insert(&market_id, &market);
    }

    // View method to get the total staked amount on a specific market
    pub fn get_total_staked(&self, market_id: u64) -> Balance {
        let market = self.markets.get(&market_id).expect("Market not found");
        market.total_staked
    }
}

/*
 * The rest of this file holds the inline tests for the code above
 * Learn more about Rust tests: https://doc.rust-lang.org/book/ch11-01-writing-tests.html
 */
#[cfg(test)]
mod tests {
}
