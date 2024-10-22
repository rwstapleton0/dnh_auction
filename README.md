# dnh_auction

Doubles and Halves auction!
Double the current bid = half the time remaining.

TODO: let cap holder end auction if no bids.

rules:
A Double bid is the max bid.
Set a percentage for minimum bid.
auction starts when the first bid is made

**user input option:**
    start_bid: u64,
    auction_time_length: u64,
    minimum_bid_percent: u64,
    end_phase_time_length: u64,

# New Functions

calling new will create a shared Auction<T> which is used to manage the auction.

### new_cap then new
Use when creating a collection, owner holds a single AuctionCap<T> for all auctions creating cap requires a Publisher.

public fun new_cap<T: key + store>(
    pub: &Publisher, 
    ctx: &mut TxContext
): AuctionCap<T>

public fun new<T: key + store>(
    cap: &AuctionCap<T>,
    item: T,
    start_bid: u64,
    auction_time_length: u64,
    minimum_bid_percent: u64,
    end_phase_time_length: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): ID


### new_with_cap
Use when creating indivual auctions. will return an AuctionCap<T> for that single auction. calls new function internally.

public fun new_with_cap<T: key + store>(
    item: T,
    start_bid: u64,
    auction_time_length: u64,
    minimum_bid_percent: u64,
    end_phase_time_length: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): AuctionCap<T>


## Auction Functionality

new or new_with_cap have the same functionailty from here:

### place_bid

Takes a shared Auction<T> object and a coin, a bid will be made if the coin value meets the minimum bid. If the coin value is greater than the max bid (Double the previous bid) a max bid will be placed.

public fun place_bid<T: key + store>(
    auction: &mut Auction<T>,
    coin: &mut Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
)

### take_item

Takes shared auction, requires the auction to be ended and the sender to be the highest bidder.

public fun take_item<T: key + store>(
    auction: &mut Auction<T>,
    clock: &Clock, 
    ctx: &mut TxContext,
): T

### close_auction

public fun close_auction<T: key + store>(
    mut auction: Auction<T>,
    auction_cap: &AuctionCap<T>,
    clock: &Clock, 
    ctx: &mut TxContext
): Coin<SUI>