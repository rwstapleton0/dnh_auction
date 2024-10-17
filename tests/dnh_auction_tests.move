#[test_only]
module dnh_auction::dnh_auction_tests {
    use sui::test_scenario::{Self, Scenario};
    // uncomment this line to import the module
    use sui::{clock::{Self, Clock}, package::{Self, Publisher}, coin::{Self, Coin}, sui::SUI};
    use dnh_auction::dnh_auction::{Self, AuctionCap};

    // const ENotImplemented: u64 = 0;
    const EItemStoredWrong: u64 = 900001;
    const EBidWasNotPlaced: u64 = 900002;
    const EBidderIncorrect: u64 = 900003;
    const EIncorrectPrice: u64 = 900004;
    const ECoinBalanceIncorrect: u64 = 900005;
    const ETimeWasIncorrect: u64 = 900006;

    const ONE_SUI: u64 = 1_000_000_000;
    const ONE_YEAR_IN_MS: u64 = 31_556_952_000;
    const ONE_HOUR_IN_MS: u64 = 3_600_000;
    const MININUM_BID_PERCENT: u64 = 5;

    // Create test addresses representing users
    const ADMIN: address = @0xAD;
    const USER_A: address = @0xFAA;
    const USER_B: address = @0xFAB;
    // const INITIAL_OWNER: address = @0xCAFE;

    public struct TestObject has key, store {
        id: UID,
    }

    public struct TEST_WITNESS has drop {}

    public struct AuctionProps has copy, drop {
        start_bid: u64,
        auction_time_length: u64,
        minimum_bid_percent: u64,
        end_phase_time_length: u64,
    }

    #[test_only]
    fun test_init(otw: TEST_WITNESS, ctx: &mut TxContext): Publisher {
        package::test_claim(otw, ctx)
    }

    #[test_only]
    fun test_init_n_new_auction(
        sender: address,
        mut props: Option<AuctionProps>,
    ): (Scenario, Clock) {
        let auction_data = if (props.is_some()) props.extract() else AuctionProps {
            start_bid: ONE_SUI,
            auction_time_length: ONE_YEAR_IN_MS,
            minimum_bid_percent: MININUM_BID_PERCENT,
            end_phase_time_length: ONE_HOUR_IN_MS,
        };

        let mut scenario = test_scenario::begin(sender);
        let publisher = test_init(TEST_WITNESS {}, scenario.ctx());
        let clock = clock::create_for_testing(scenario.ctx());
        let test_obj = TestObject { id: object::new(scenario.ctx()) };
        let auction_cap = dnh_auction::new_cap<TestObject>(&publisher, scenario.ctx());
        // Create Auction
        {
            dnh_auction::new<TestObject>(
                &auction_cap, 
                test_obj,
                auction_data.start_bid, 
                auction_data.auction_time_length, 
                auction_data.minimum_bid_percent, 
                auction_data.end_phase_time_length, 
                &clock,
                scenario.ctx()
            );
            transfer::public_transfer(publisher, sender);
            transfer::public_transfer(auction_cap, sender);
        };
        (scenario, clock)
    }

    #[test]
    fun test_dnh_auction() {
        let (mut scenario, mut clock) = test_init_n_new_auction(ADMIN, option::none());
        
        scenario.next_tx(ADMIN);
        let mut auction = scenario.take_shared<dnh_auction::Auction<TestObject>>();

        // place first bid
        scenario.next_tx(USER_A);
        {
            let mut coin = coin::mint_for_testing<SUI>(ONE_SUI, scenario.ctx());
            dnh_auction::place_bid(&mut auction, &mut coin, &clock, scenario.ctx());

            assert!(auction.current_bid() == ONE_SUI, EBidWasNotPlaced);
            assert!(auction.highest_bidder() == USER_A, EBidderIncorrect);

            transfer::public_transfer(coin, ADMIN);
        };

        // place double bid 2_000_000_000
        let bid_value = ONE_SUI * 2;
        scenario.next_tx(USER_B);
        {
            let mut coin = coin::mint_for_testing<SUI>(bid_value, scenario.ctx());
            dnh_auction::place_bid(&mut auction, &mut coin, &clock, scenario.ctx());

            assert!(auction.current_bid() == bid_value, EBidWasNotPlaced);
            assert!(auction.highest_bidder() == USER_B, EBidderIncorrect);

            transfer::public_transfer(coin, ADMIN);
        };

        // set time to end of auction
        clock.set_for_testing(auction.finishes_at());
        scenario.next_tx(USER_B);
        {
            let item = auction.take_item(&clock, scenario.ctx());
            transfer::public_transfer(item, ADMIN);
        };

        scenario.next_tx(ADMIN);
        {
            let auction_cap = scenario.take_from_sender<AuctionCap<TestObject>>();

            let coin = dnh_auction::close_auction(auction, &auction_cap, &clock, scenario.ctx());

            transfer::public_transfer(coin, ADMIN);
            scenario.return_to_sender(auction_cap);
        };

        clock.destroy_for_testing();
        scenario.end();
    }

    /* Close Auction */

    #[test]
    fun test_close_auction_with_transfer() {
        let (mut scenario, mut clock) = test_init_n_new_auction(ADMIN, option::none());
        
        scenario.next_tx(ADMIN);
        let mut auction = scenario.take_shared<dnh_auction::Auction<TestObject>>();

        // place first bid
        scenario.next_tx(USER_A);
        {
            let mut coin = coin::mint_for_testing<SUI>(ONE_SUI, scenario.ctx());
            dnh_auction::place_bid(&mut auction, &mut coin, &clock, scenario.ctx());
            transfer::public_transfer(coin, ADMIN);
        };

        // place double bid 2_000_000_000
        let bid_value = ONE_SUI * 2;
        scenario.next_tx(USER_B);
        {
            let mut coin = coin::mint_for_testing<SUI>(bid_value, scenario.ctx());
            dnh_auction::place_bid(&mut auction, &mut coin, &clock, scenario.ctx());
            transfer::public_transfer(coin, ADMIN);
        };

        // set time to end of auction
        clock.set_for_testing(auction.finishes_at());
        // close auction, item will be return here too.
        scenario.next_tx(ADMIN);
        {
            let auction_cap = scenario.take_from_sender<AuctionCap<TestObject>>();

            let coin = dnh_auction::close_auction(auction, &auction_cap, &clock, scenario.ctx());

            transfer::public_transfer(coin, ADMIN);
            scenario.return_to_sender(auction_cap);
        };

        scenario.next_tx(USER_B);
        {   
            // object will have been returned from last tx. would fail to take_from_sender if wasnt returned correctly
            let item = scenario.take_from_sender<TestObject>();
            scenario.return_to_sender(item);
        };

        clock.destroy_for_testing();
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = ::dnh_auction::dnh_auction::EAuctionHasNotEnded)]
    fun test_close_auction_before_end() {
        let (mut scenario, mut clock) = test_init_n_new_auction(ADMIN, option::none());
        
        scenario.next_tx(ADMIN);
        let mut auction = scenario.take_shared<dnh_auction::Auction<TestObject>>();

        // place first bid
        scenario.next_tx(USER_A);
        {
            let mut coin = coin::mint_for_testing<SUI>(ONE_SUI, scenario.ctx());
            dnh_auction::place_bid(&mut auction, &mut coin, &clock, scenario.ctx());
            transfer::public_transfer(coin, ADMIN);
        };

        // set time to 10ms before end of auction
        clock.set_for_testing(auction.finishes_at() - 10);
        // close auction, item will be return here too.
        scenario.next_tx(ADMIN);
        {
            let auction_cap = scenario.take_from_sender<AuctionCap<TestObject>>();
            
            let coin = dnh_auction::close_auction(auction, &auction_cap, &clock, scenario.ctx());

            transfer::public_transfer(coin, ADMIN);
            scenario.return_to_sender(auction_cap);
        };

        clock.destroy_for_testing();
        scenario.end();
    }

    /* Take Item */

    #[test]
    fun test_take_item() {
        let (mut scenario, mut clock) = test_init_n_new_auction(ADMIN, option::none());
        
        scenario.next_tx(ADMIN);
        let mut auction = scenario.take_shared<dnh_auction::Auction<TestObject>>();

        // place first bid
        scenario.next_tx(USER_A);
        {
            let mut coin = coin::mint_for_testing<SUI>(ONE_SUI, scenario.ctx());
            dnh_auction::place_bid(&mut auction, &mut coin, &clock, scenario.ctx());
            transfer::public_transfer(coin, ADMIN);
        };

        // place double bid 2_000_000_000
        let bid_value = ONE_SUI * 2;
        scenario.next_tx(USER_B);
        {
            let mut coin = coin::mint_for_testing<SUI>(bid_value, scenario.ctx());
            dnh_auction::place_bid(&mut auction, &mut coin, &clock, scenario.ctx());
            transfer::public_transfer(coin, ADMIN);
        };

        // set time to end of auction
        clock.set_for_testing(auction.finishes_at());
        scenario.next_tx(USER_B);
        {
            let item = auction.take_item(&clock, scenario.ctx());

            transfer::public_transfer(item, ADMIN);
        };

        test_scenario::return_shared(auction);
        clock.destroy_for_testing();
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = ::dnh_auction::dnh_auction::EAuctionHasNotEnded)]
    fun test_take_item_to_early() {
        let (mut scenario, mut clock) = test_init_n_new_auction(ADMIN, option::none());
        
        scenario.next_tx(ADMIN);
        let mut auction = scenario.take_shared<dnh_auction::Auction<TestObject>>();

        // place first bid
        scenario.next_tx(USER_A);
        {
            let mut coin = coin::mint_for_testing<SUI>(ONE_SUI, scenario.ctx());
            dnh_auction::place_bid(&mut auction, &mut coin, &clock, scenario.ctx());
            transfer::public_transfer(coin, ADMIN);
        };

        // place double bid 2_000_000_000
        let bid_value = ONE_SUI * 2;
        scenario.next_tx(USER_B);
        {
            let mut coin = coin::mint_for_testing<SUI>(bid_value, scenario.ctx());
            dnh_auction::place_bid(&mut auction, &mut coin, &clock, scenario.ctx());
            transfer::public_transfer(coin, ADMIN);
        };

        // set time to end of auction
        clock.set_for_testing(auction.finishes_at() - 10);
        scenario.next_tx(USER_B);
        {
            let item = auction.take_item(&clock, scenario.ctx());

            transfer::public_transfer(item, ADMIN);
        };

        test_scenario::return_shared(auction);
        clock.destroy_for_testing();
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = ::dnh_auction::dnh_auction::EAddressNotHighestBidder)]
    fun test_only_highest_bid_can_take_item() {
        let (mut scenario, mut clock) = test_init_n_new_auction(ADMIN, option::none());
        
        scenario.next_tx(ADMIN);
        let mut auction = scenario.take_shared<dnh_auction::Auction<TestObject>>();

        // place first bid
        scenario.next_tx(USER_A);
        {
            let mut coin = coin::mint_for_testing<SUI>(ONE_SUI, scenario.ctx());
            dnh_auction::place_bid(&mut auction, &mut coin, &clock, scenario.ctx());
            transfer::public_transfer(coin, ADMIN);
        };

        // place double bid 2_000_000_000
        let bid_value = ONE_SUI * 2;
        scenario.next_tx(USER_B);
        {
            let mut coin = coin::mint_for_testing<SUI>(bid_value, scenario.ctx());
            dnh_auction::place_bid(&mut auction, &mut coin, &clock, scenario.ctx());
            transfer::public_transfer(coin, ADMIN);
        };

        // set time to end of auction
        clock.set_for_testing(auction.finishes_at());
        scenario.next_tx(USER_A);
        {
            let item = auction.take_item(&clock, scenario.ctx());
            transfer::public_transfer(item, ADMIN);
        };

        test_scenario::return_shared(auction);
        clock.destroy_for_testing();
        scenario.end();
    }

    /* Double Bid */

    #[test]
    fun test_double_bid() {
        let (mut scenario, clock) = test_init_n_new_auction(ADMIN, option::none());
        
        scenario.next_tx(ADMIN);
        let mut auction = scenario.take_shared<dnh_auction::Auction<TestObject>>();

        // place first bid
        scenario.next_tx(USER_A);
        {
            let mut coin = coin::mint_for_testing<SUI>(ONE_SUI, scenario.ctx());
            dnh_auction::place_bid(&mut auction, &mut coin, &clock, scenario.ctx());
            transfer::public_transfer(coin, ADMIN);
        };

        // place double bid 2_000_000_000
        let bid_value = ONE_SUI * 2;
        scenario.next_tx(USER_B);
        {
            assert!(auction.finishes_at() == auction.auction_time_length(), ETimeWasIncorrect);
            
            let mut coin = coin::mint_for_testing<SUI>(bid_value, scenario.ctx());
            dnh_auction::place_bid(&mut auction, &mut coin, &clock, scenario.ctx());

            assert!(auction.current_bid() == bid_value, EBidWasNotPlaced);
            assert!(auction.highest_bidder() == USER_B, EBidderIncorrect);

            // As per dnh rules: double bid, means half time.
            assert!(auction.finishes_at() == auction.auction_time_length() / 2, ETimeWasIncorrect);

            transfer::public_transfer(coin, ADMIN);
        };

        test_scenario::return_shared(auction);
        clock.destroy_for_testing();
        scenario.end();
    }

    #[test]
    fun test_double_bid_sets_finishes_at_equal_to_end_phase_time() {
        let (mut scenario, mut clock) = test_init_n_new_auction(ADMIN, option::none());
        
        scenario.next_tx(ADMIN);
        let mut auction = scenario.take_shared<dnh_auction::Auction<TestObject>>();

        // place first bid
        scenario.next_tx(USER_A);
        {
            let mut coin = coin::mint_for_testing<SUI>(ONE_SUI, scenario.ctx());
            dnh_auction::place_bid(&mut auction, &mut coin, &clock, scenario.ctx());
            transfer::public_transfer(coin, ADMIN);
        };

        // place double bid 2_000_000_000
        let bid_value = ONE_SUI * 2;
        scenario.next_tx(USER_B);
        {
            let in_end_phase_time = auction.finishes_at() - (auction.end_phase_time_length() + 10);
            // debug::print(&finishes_at);  [debug] 31556952000
            // debug::print(&in_end_phase_time); [debug] 31553351990

            // set time to 10 ms before end phase.
            clock.set_for_testing(in_end_phase_time);

            let mut coin = coin::mint_for_testing<SUI>(bid_value, scenario.ctx());
            dnh_auction::place_bid(&mut auction, &mut coin, &clock, scenario.ctx());

            assert!(auction.current_bid() == bid_value, EBidWasNotPlaced);
            assert!(auction.highest_bidder() == USER_B, EBidderIncorrect);

            // As per dnh rules: double bid, means half time.
            // time_remaining should be end_phase_time
            let time_remaining = auction.finishes_at() - clock.timestamp_ms();
            assert!(time_remaining == auction.end_phase_time_length(), ETimeWasIncorrect);

            transfer::public_transfer(coin, ADMIN);
        };

        test_scenario::return_shared(auction);
        clock.destroy_for_testing();
        scenario.end();
    }

    #[test]
    fun test_double_bid_while_end_phase() {
        let (mut scenario, mut clock) = test_init_n_new_auction(ADMIN, option::none());
        
        scenario.next_tx(ADMIN);
        let mut auction = scenario.take_shared<dnh_auction::Auction<TestObject>>();

        // place first bid
        scenario.next_tx(USER_A);
        {
            let mut coin = coin::mint_for_testing<SUI>(ONE_SUI, scenario.ctx());
            dnh_auction::place_bid(&mut auction, &mut coin, &clock, scenario.ctx());
            transfer::public_transfer(coin, ADMIN);
        };

        // place double bid 2_000_000_000
        let bid_value = ONE_SUI * 2;
        scenario.next_tx(USER_B);
        {
            let finishes_at = auction.finishes_at();
            let in_end_phase_time = finishes_at - (auction.end_phase_time_length() - 10);
            // debug::print(&finishes_at);  [debug] 31556952000
            // debug::print(&in_end_phase_time); [debug] 31553352010

            // set time to 10 ms into end phase.
            clock.set_for_testing(in_end_phase_time);

            // try to double bid.
            let mut coin = coin::mint_for_testing<SUI>(bid_value, scenario.ctx());
            dnh_auction::place_bid(&mut auction, &mut coin, &clock, scenario.ctx());

            assert!(auction.current_bid() == bid_value, EBidWasNotPlaced);
            assert!(auction.highest_bidder() == USER_B, EBidderIncorrect);

            // As per dnh rules: double bid, means half time.
            // finishes_at should be unchanged, double_bid but is in end_phase
            assert!(auction.finishes_at() == finishes_at, ETimeWasIncorrect);

            transfer::public_transfer(coin, ADMIN);
        };

        test_scenario::return_shared(auction);
        clock.destroy_for_testing();
        scenario.end();
    }

    /* Return Bid */

    #[test]
    fun test_previous_bid_returned() {
        let (mut scenario, clock) = test_init_n_new_auction(ADMIN, option::none());
        
        scenario.next_tx(ADMIN);

        let mut auction = scenario.take_shared<dnh_auction::Auction<TestObject>>();
        // place first bid
        scenario.next_tx(USER_A);
        {
            let mut coin = coin::mint_for_testing<SUI>(ONE_SUI, scenario.ctx());
            dnh_auction::place_bid(&mut auction, &mut coin, &clock, scenario.ctx());

            assert!(coin.value() == 0, ECoinBalanceIncorrect);
            transfer::public_transfer(coin, ADMIN);
        };

        // place minimum bid 1_050_000_000
        let bid_value = ONE_SUI + (ONE_SUI * MININUM_BID_PERCENT) / 100;
        scenario.next_tx(USER_B);
        {
            let mut coin = coin::mint_for_testing<SUI>(bid_value, scenario.ctx());
            dnh_auction::place_bid(&mut auction, &mut coin, &clock, scenario.ctx());

            assert!(auction.current_bid() == bid_value, EBidWasNotPlaced);
            assert!(auction.highest_bidder() == USER_B, EBidderIncorrect);

            transfer::public_transfer(coin, ADMIN);
        };

        // previous bid returned.
        scenario.next_tx(USER_A);
        {
            let coin = scenario.take_from_sender<Coin<SUI>>();
            assert!(coin.value() == ONE_SUI, ECoinBalanceIncorrect);
            transfer::public_transfer(coin, ADMIN);
        };

        test_scenario::return_shared(auction);
        clock.destroy_for_testing();
        scenario.end();
    }

    /* Min Bid */

    #[test]
    fun test_min_bid() {
        let (mut scenario, clock) = test_init_n_new_auction(ADMIN, option::none());
        
        scenario.next_tx(ADMIN);

        let mut auction = scenario.take_shared<dnh_auction::Auction<TestObject>>();
        // place first bid
        scenario.next_tx(USER_A);
        {
            let mut coin = coin::mint_for_testing<SUI>(ONE_SUI, scenario.ctx());
            dnh_auction::place_bid(&mut auction, &mut coin, &clock, scenario.ctx());

            transfer::public_transfer(coin, ADMIN);
        };

        // place minimum bid 1_050_000_000
        let bid_value = ONE_SUI + (ONE_SUI * MININUM_BID_PERCENT) / 100;
        scenario.next_tx(USER_B);
        {

            let mut coin = coin::mint_for_testing<SUI>(bid_value, scenario.ctx());
            dnh_auction::place_bid(&mut auction, &mut coin, &clock, scenario.ctx());

            assert!(auction.current_bid() == bid_value, EBidWasNotPlaced);
            assert!(auction.highest_bidder() == USER_B, EBidderIncorrect);

            transfer::public_transfer(coin, ADMIN);
        };

        test_scenario::return_shared(auction);
        clock.destroy_for_testing();
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = ::dnh_auction::dnh_auction::EInvalidBid)]
    fun test_min_bid_not_reached() {
        let (mut scenario, clock) = test_init_n_new_auction(ADMIN, option::none());
        scenario.next_tx(ADMIN);
        let mut auction = scenario.take_shared<dnh_auction::Auction<TestObject>>();

        // place first bid
        scenario.next_tx(USER_A);
        {
            let mut coin = coin::mint_for_testing<SUI>(ONE_SUI, scenario.ctx());
            dnh_auction::place_bid(&mut auction, &mut coin, &clock, scenario.ctx());
            transfer::public_transfer(coin, ADMIN);
        };

        // place below minimum bid 1_040_000_000, 4% instead of minimum of 5%.
        let bid_value = ONE_SUI + (ONE_SUI * MININUM_BID_PERCENT - 1) / 100;
        scenario.next_tx(USER_B);
        {
            let mut coin = coin::mint_for_testing<SUI>(bid_value, scenario.ctx());
            dnh_auction::place_bid(&mut auction, &mut coin, &clock, scenario.ctx());

            transfer::public_transfer(coin, ADMIN);
        };
        test_scenario::return_shared(auction);
        clock.destroy_for_testing();
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = ::dnh_auction::dnh_auction::EAuctionHasEnded)]
    fun test_auction_ended() {
        let (mut scenario, mut clock) = test_init_n_new_auction(ADMIN, option::none());
        scenario.next_tx(ADMIN);
        let mut auction = scenario.take_shared<dnh_auction::Auction<TestObject>>();

        // place first bid
        scenario.next_tx(USER_A);
        {
            let mut coin = coin::mint_for_testing<SUI>(ONE_SUI, scenario.ctx());
            dnh_auction::place_bid(&mut auction, &mut coin, &clock, scenario.ctx());
            transfer::public_transfer(coin, ADMIN);
        };

        // place minimum bid 1_050_000_000
        let bid_value = ONE_SUI + (ONE_SUI * MININUM_BID_PERCENT) / 100;
        scenario.next_tx(USER_B);
        {
            // Set Clock to auction.finishes_at
            clock.set_for_testing(auction.finishes_at());
            
            // try to place bid, fails here.
            let mut coin = coin::mint_for_testing<SUI>(bid_value, scenario.ctx());
            dnh_auction::place_bid(&mut auction, &mut coin, &clock, scenario.ctx());
            transfer::public_transfer(coin, ADMIN);
        };
        test_scenario::return_shared(auction);
        clock.destroy_for_testing();
        scenario.end();
    }

    #[test]
    fun test_first_bid_return_coin() {
        let (mut scenario, clock) = test_init_n_new_auction(ADMIN, option::none());

        // place bid
        scenario.next_tx(USER_A);
        {
            let mut auction = scenario.take_shared<dnh_auction::Auction<TestObject>>();

            // mint 2 SUI, as start bid is 1 SUI, should have 1 SUI remaining.
            let mut coin = coin::mint_for_testing<SUI>(ONE_SUI * 2, scenario.ctx());
            dnh_auction::place_bid(&mut auction, &mut coin, &clock, scenario.ctx());

            assert!(auction.current_bid() == ONE_SUI, EBidWasNotPlaced);
            assert!(auction.highest_bidder() == USER_A, EBidderIncorrect);
            assert!(coin.value() == ONE_SUI, EIncorrectPrice);

            test_scenario::return_shared(auction);
            transfer::public_transfer(coin, ADMIN);
        };

        clock.destroy_for_testing();
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = ::dnh_auction::dnh_auction::EInvalidBid)]
    fun test_first_bid_insufficient() {
        let (mut scenario, clock) = test_init_n_new_auction(ADMIN, option::none());

        // place bid
        scenario.next_tx(USER_A);
        {
            let mut auction = scenario.take_shared<dnh_auction::Auction<TestObject>>();

            // mint 100 mist, as start bid is 1 SUI so should fail.
            let mut coin = coin::mint_for_testing<SUI>(100, scenario.ctx());
            dnh_auction::place_bid(&mut auction, &mut coin, &clock, scenario.ctx());

            test_scenario::return_shared(auction);
            transfer::public_transfer(coin, ADMIN);
        };

        clock.destroy_for_testing();
        scenario.end();
    }

    #[test]
    fun test_new_dnh_auction() {
        let mut scenario = test_scenario::begin(ADMIN);
        let ctx = scenario.ctx();
        let clock = clock::create_for_testing(ctx);
        let pub = test_init(TEST_WITNESS {}, ctx);
        let test_obj = TestObject { id: object::new(ctx) };
        let test_obj_id = object::id(&test_obj);
        {
            let auction_cap = dnh_auction::new_cap<TestObject>(&pub, ctx);
            dnh_auction::new<TestObject>(
                &auction_cap, 
                test_obj,
                ONE_SUI, 
                ONE_YEAR_IN_MS, 
                5, 
                ONE_HOUR_IN_MS, 
                &clock,
                ctx
            );
            transfer::public_transfer(auction_cap, ADMIN);
        };

        scenario.next_tx(ADMIN);
        {
            let auction = scenario.take_shared<dnh_auction::Auction<TestObject>>();
            let item = option::borrow<TestObject>(dnh_auction::item<TestObject>(&auction));
            assert!( test_obj_id == object::borrow_id(item), EItemStoredWrong);

            test_scenario::return_shared(auction)
        };
        clock.destroy_for_testing();
        transfer::public_transfer(pub, ADMIN);
        scenario.end();
    }
}
