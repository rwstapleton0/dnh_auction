#[test_only]
module dnh_auction::dnh_auction_with_cap_tests {
    // uncomment this line to import the module
    use sui::clock;
    use dnh_auction::dnh_auction;

    // const ENotImplemented: u64 = 0;
    const EItemStoredWrong: u64 = 900001;

    const ONE_SUI: u64 = 1_000_000_000;
    const ONE_YEAR_IN_MS: u64 = 31_556_952_000;
    const ONE_HOUR_IN_MS: u64 = 3_600_000;

    // Create test addresses representing users
    const ADMIN: address = @0xAD;
    // const INITIAL_OWNER: address = @0xCAFE;

    public struct TestObject has key, store {
        id: UID,
    }

    #[test]
    fun test_dnh_auction_with_cap() {
        use sui::test_scenario;


        // First transaction to emulate module initialization
        let mut scenario = test_scenario::begin(ADMIN);
        let ctx = scenario.ctx();
        let clock = clock::create_for_testing(ctx);
        let test_obj = TestObject { 
            id: object::new(ctx)
        };
        let test_obj_id = object::id(&test_obj);
        {
            let auction_cap = dnh_auction::new_with_cap<TestObject>(
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

            // Return the Forge object to the object pool
            test_scenario::return_shared(auction)
        };
        clock.destroy_for_testing();
        scenario.end();
    }

    #[test]
    fun test_new_dnh_auction_with_cap() {
        use sui::test_scenario;

        // First transaction to emulate module initialization
        let mut scenario = test_scenario::begin(ADMIN);
        let ctx = scenario.ctx();
        let clock = clock::create_for_testing(ctx);
        let test_obj = TestObject { 
            id: object::new(ctx)
        };
        let test_obj_id = object::id(&test_obj);
        {
            let auction_cap = dnh_auction::new_with_cap<TestObject>(
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

            // Return the Forge object to the object pool
            test_scenario::return_shared(auction)
        };
        clock.destroy_for_testing();
        scenario.end();
    }

    // #[test, expected_failure(abort_code = ::dnh_auction::dnh_auction_tests::ENotImplemented)]
    // fun test_dnh_auction_fail() {
    //     abort ENotImplemented
    // }


}
