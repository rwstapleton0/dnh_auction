/// Module: dnh_auction
module dnh_auction::dnh_auction {

    use sui::{coin::{Self, Coin}, clock::Clock, event, 
    package::Publisher, sui::SUI, balance::{Self, Balance}};

    const EAddressNotHighestBidder: u64 = 100001;
    const EAuctionHasEnded: u64 = 100002;
    const EAuctionHasNotEnded: u64 = 100003;
    const EInvalidBid: u64 = 100004;
    const ECallerNotAdmin: u64 = 100005;
    const ENotOwner: u64 = 100006;

    public struct Auction<T: key + store> has key, store {
        id: UID,
        item: Option<T>,
        start_bid: u64,
        auction_time_length: u64,
        minimum_bid_percent: u64,
        end_phase_time_length: u64,
        current_bid: u64,
        highest_bidder: address,
        finishes_at: u64,
        is_started: bool,
        balance: Balance<SUI>,
        auction_cap: ID,
    }

    public struct AuctionCap<phantom T> has key, store {
        id: UID
    }

    // use type to add specific data?
    public struct AuctionCreated<phantom T> has copy, drop {
        auction_id: ID,
        item_id: ID,
        start_bid: u64,
        auction_time_length: u64,
        minimum_bid_percent: u64,
        end_phase_time_length: u64,
        timestamp: u64
    }

    public struct AuctionEnded<phantom T> has copy, drop {
        auction_id: ID,
        highest_bidder: address,
        final_bid: u64,
        timestamp: u64
    }

    public struct BidPlaced<phantom T> has copy, drop {
        auction_id: ID,
        highest_bidder: address,
        current_bid: u64,
        finishes_at: u64,
        timestamp: u64
    }

    public fun id<T: key + store>(auction: &Auction<T>): &ID { auction.id.as_inner() }

    public fun item<T: key + store>(auction: &Auction<T>): &Option<T> { &auction.item }
    
    public fun start_bid<T: key + store>(auction: &Auction<T>): u64 { auction.start_bid }

    public fun auction_time_length<T: key + store>(auction: &Auction<T>): u64 { auction.auction_time_length }

    public fun minimum_bid_percent<T: key + store>(auction: &Auction<T>): u64 { auction.minimum_bid_percent }
    
    public fun end_phase_time_length<T: key + store>(auction: &Auction<T>): u64 { auction.end_phase_time_length }
    
    public fun current_bid<T: key + store>(auction: &Auction<T>): u64 { auction.current_bid }
    
    public fun highest_bidder<T: key + store>(auction: &Auction<T>): address { auction.highest_bidder }
    
    public fun finishes_at<T: key + store>(auction: &Auction<T>): u64 { auction.finishes_at }

    public fun is_started<T: key + store>(auction: &Auction<T>): bool { auction.is_started }

    public fun balance<T: key + store>(auction: &Auction<T>): u64 { auction.balance.value() }

    public fun auction_cap<T: key + store>(auction: &Auction<T>): &ID { &auction.auction_cap }
    
    // Does sender own the package of T through a OTW ??
    // public fun new_cap<OTW: drop, T: key + store>(otw: OTW, ctx: &mut TxContext): AuctionCap<T> {
    
    public fun new_cap<T: key + store>(pub: &Publisher, ctx: &mut TxContext): AuctionCap<T> {
        assert!(is_authorized<T>(pub), ENotOwner);
        AuctionCap<T> {
            id: object::new(ctx)
        }
    }

    public fun new<T: key + store>(
        cap: &AuctionCap<T>,
        item: T,
        start_bid: u64,
        auction_time_length: u64,
        minimum_bid_percent: u64,
        end_phase_time_length: u64,
        clock: &Clock,
        ctx: &mut TxContext,
    ): ID {
        let uid = object::new(ctx);
        let id = object::uid_to_inner(&uid);
        event::emit(AuctionCreated<T> {
            auction_id: id,
            item_id: object::id(&item),
            start_bid,
            auction_time_length,
            minimum_bid_percent,
            end_phase_time_length,
            timestamp: clock.timestamp_ms()
        });
        transfer::share_object(Auction<T> {
            id: uid,
            item: option::some(item),
            finishes_at: 0,
            start_bid,
            auction_time_length,
            minimum_bid_percent,
            end_phase_time_length,
            current_bid: 0,
            highest_bidder: ctx.sender(),
            is_started: false,
            balance: balance::zero<SUI>(),
            auction_cap: object::id(cap),
        });
        id
    }

    // Single use auction returns cap, will add return cap on auction end.
    public fun new_with_cap<T: key + store>(
        item: T,
        start_bid: u64,
        auction_time_length: u64,
        minimum_bid_percent: u64,
        end_phase_time_length: u64,
        clock: &Clock,
        ctx: &mut TxContext,
    ): AuctionCap<T> {
        let auction_cap = AuctionCap<T> {
            id: object::new(ctx)
        };

        new<T>(
            &auction_cap,
            item, 
            start_bid,
            auction_time_length,
            minimum_bid_percent, 
            end_phase_time_length,
            clock,
            ctx,
        );

        auction_cap
    }

    public fun place_bid<T: key + store>(
        auction: &mut Auction<T>,
        coin: &mut Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let timestamp = clock.timestamp_ms();

        if (!auction.is_started) {
            first_bid(auction, coin, timestamp, ctx);
            return
        };

        // assert time remaining & minimum_bid
        let bid_value = coin.value();
        let minimum_bid = auction.current_bid + (auction.current_bid * auction.minimum_bid_percent) / 100;
        assert!(timestamp < auction.finishes_at, EAuctionHasEnded);
        assert!(bid_value >= minimum_bid, EInvalidBid);

        // return previous bid.
        transfer::public_transfer(
            coin::split(coin, auction.current_bid, ctx),
            auction.highest_bidder
        );

        // if bid is over 200% of previous bid, 
        let time_remaining = auction.finishes_at - timestamp;
        let max_bid = auction.current_bid * 2;
        if (
            bid_value >= max_bid &&
            time_remaining > auction.end_phase_time_length
        ) {
            double_bid(auction, coin, timestamp, ctx);
        } else  {
            normal_bid(auction, coin, bid_value, ctx);
        };

        auction.highest_bidder = ctx.sender();

        event::emit(BidPlaced<T> {
            auction_id: object::id(auction),
            highest_bidder: auction.highest_bidder,
            current_bid: auction.current_bid,
            finishes_at: auction.finishes_at,
            timestamp: clock.timestamp_ms()
        })

    }

    public fun take_item<T: key + store>(
        auction: &mut Auction<T>,
        clock: &Clock, 
        ctx: &mut TxContext,
    ): T {
        assert!(auction.highest_bidder == ctx.sender(), EAddressNotHighestBidder);
        assert!(clock.timestamp_ms() >= auction.finishes_at, EAuctionHasNotEnded);

        option::extract(&mut auction.item) // needs to go to kiosk?
    }

    public fun close_auction<T: key + store>(
        mut auction: Auction<T>,
        auction_cap: &AuctionCap<T>,
        clock: &Clock, 
        ctx: &mut TxContext
    ): Coin<SUI> {
        assert!(auction.auction_cap == object::id(auction_cap), ECallerNotAdmin);
        assert!(clock.timestamp_ms() >= auction.finishes_at, EAuctionHasNotEnded);

        if (option::is_some(&auction.item)) {
            transfer::public_transfer(
                option::extract(&mut auction.item), 
                auction.highest_bidder
            )
        };

        event::emit(AuctionEnded<T> {
            auction_id: object::id(&auction),
            highest_bidder: auction.highest_bidder,
            final_bid: auction.current_bid,
            timestamp: clock.timestamp_ms()
        });

        let Auction<T> {
            id, item, mut balance, 
            start_bid: _, auction_time_length: _,
            minimum_bid_percent: _, end_phase_time_length: _,
            current_bid: _, highest_bidder: _, finishes_at: _,
            is_started: _, auction_cap: _,
        } = auction;

        option::destroy_none(item);

        // Transfer funds to the seller
        let balace_value = balance.value();
        let profit = coin::take(&mut balance, balace_value, ctx);
        balance.destroy_zero();

        // delete auction.
        object::delete(id);

        profit
    }

    fun first_bid<T: key + store>(
        auction: &mut Auction<T>,
        coin: &mut Coin<SUI>,
        timestamp: u64,
        ctx: &mut TxContext,
    ) {
        assert!(coin.value() >= auction.start_bid, EInvalidBid);

        let to_add = coin.split(auction.start_bid, ctx);
        balance::join(&mut auction.balance, coin::into_balance(to_add));

        auction.current_bid = auction.start_bid;
        auction.highest_bidder = ctx.sender();
        auction.finishes_at = timestamp + auction.auction_time_length;
        auction.is_started = true;

        event::emit(BidPlaced<T> {
            auction_id: object::id(auction),
            highest_bidder: auction.highest_bidder,
            current_bid: auction.current_bid,
            finishes_at: auction.finishes_at,
            timestamp
        });
    }

    fun double_bid<T: key + store>(
        auction: &mut Auction<T>,
        coin: &mut Coin<SUI>,
        timestamp: u64,
        ctx: &mut TxContext,
    ) {
        let max_bid = auction.current_bid * 2;
        let to_transfer = max_bid - auction.current_bid;

        let to_add = coin.split(to_transfer, ctx);
        balance::join(&mut auction.balance, coin::into_balance(to_add));

        auction.current_bid = max_bid;

        let half_time_remaining = (auction.finishes_at - timestamp) / 2;
        if (half_time_remaining > auction.end_phase_time_length) {
            auction.finishes_at = auction.finishes_at - half_time_remaining;
        } else {
            auction.finishes_at = timestamp + auction.end_phase_time_length;
        }
    }

    fun normal_bid<T: key + store>(
        auction: &mut Auction<T>,
        coin: &mut Coin<SUI>,
        bid_value: u64,
        ctx: &mut TxContext,
    ) {
        let to_transfer = bid_value - auction.current_bid;

        let to_add = coin.split(to_transfer , ctx);
        balance::join(&mut auction.balance, coin::into_balance(to_add));

        auction.current_bid = bid_value;
    }

    public fun is_authorized<T: key>(pub: &Publisher): bool {
        pub.from_package<T>()
    }
}
