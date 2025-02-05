module admin::profile_nft {
    use std::error;
    use std::signer;
    use std::vector;
    use std::string::{String};
    use aptos_framework::account;
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::timestamp;
    use aptos_token::token::{Self, TokenDataId, TokenId};
    use aptos_token::token::create_token_data_id;

    // Error codes
    const ENO_CAPABILITIES: u64 = 1;
    const ECONTRACT_NOT_INITIALIZED: u64 = 2;
    const EMINTING_DISABLED: u64 = 3;
    const EMAX_SUPPLY_EXCEEDED: u64 = 4;
    const ENFT_NOT_MINTED: u64  = 5;

    // NFT collection configuration
    struct CollectionConfig has key {
        collection_name: String,
        description: String,
        base_uri: String,
        max_supply: u64,
        minted_count: u64,
        minting_enabled: bool,
        token_minting_events: EventHandle<TokenMintingEvent>,
        point_update_events: EventHandle<PointUpdateEvent>,
    }

    struct PointSystem has key {
        token_id: TokenId,
        point: u64
    }

    // Token minting event
    struct TokenMintingEvent has drop, store {
        token_id: TokenId,
        token_data_id: TokenDataId,
        minter: address,
        timestamp: u64,
    }

    // Profile point update event
    struct PointUpdateEvent has drop, store {
        updated_by: address,
        token_id: TokenId,
        new_point: u64,
        timestamp: u64,
    }

    // Initialize NFT collection
    public entry fun initialize_collection(
        account: &signer,
        collection_name: String,
        description: String,
        base_uri: String,
        max_supply: u64,
    ) { 
        // Initialize collection
        token::create_collection_script(
            account,
            collection_name,
            description,
            base_uri,
            max_supply,
            vector::empty<bool>(),
        );

        // Store collection configuration
        move_to(account, CollectionConfig {
            collection_name,
            description,
            base_uri,
            max_supply,
            minted_count: 0,
            minting_enabled: true,
            token_minting_events: account::new_event_handle<TokenMintingEvent>(account),
            point_update_events: account::new_event_handle<PointUpdateEvent>(account),
        });
    }

    // Mint new NFT
    public entry fun mint_token(
        account: &signer,
        token_name: String,
    ) acquires CollectionConfig {
        let account_addr = signer::address_of(account);
        
        // Get collection config
        let collection_config = borrow_global_mut<CollectionConfig>(@admin);
        
        // Verify minting is enabled
        assert!(collection_config.minting_enabled, error::invalid_state(EMINTING_DISABLED));
        
        // Verify max supply not exceeded
        assert!(
            collection_config.minted_count < collection_config.max_supply,
            error::invalid_state(EMAX_SUPPLY_EXCEEDED)
        );

        // Create token data id
        let token_data_id = create_token_data_id(
            @admin,
            collection_config.collection_name,
            token_name
        );

        // Mint token
        let token_id = token::mint_token(
            account,
            token_data_id,
            1, // Amount
        );

        // Increment minted count
        collection_config.minted_count = collection_config.minted_count + 1;

        // Initialize point system
        let point_system = PointSystem {
            token_id,
            point: 0
        };

        // Move to account
        move_to(account, point_system);

        // Emit minting event
        event::emit_event(
            &mut collection_config.token_minting_events,
            TokenMintingEvent {
                token_id,
                token_data_id,
                minter: account_addr,
                timestamp: timestamp::now_seconds(),
            },
        );
    }

    // Toggle minting status
    public entry fun toggle_minting(account: &signer) acquires CollectionConfig {
        let account_addr = signer::address_of(account);
        assert!(account_addr == @admin, error::permission_denied(ENO_CAPABILITIES));
        
        let collection_config = borrow_global_mut<CollectionConfig>(@admin);
        collection_config.minting_enabled = !collection_config.minting_enabled;
    }

    // Update user point
    public(friend) entry fun update_profile_point(account: &signer, user: address, new_point: u64) acquires PointSystem, CollectionConfig {
        assert!(exists<PointSystem>(user), ENFT_NOT_MINTED);
        let account_addr = signer::address_of(account);
        let point_system = borrow_global_mut<PointSystem>(user);
        point_system.point = new_point;
        let collection_config = borrow_global_mut<CollectionConfig>(@admin);
        event::emit_event(
            &mut collection_config.point_update_events,
            PointUpdateEvent {
                updated_by: account_addr,
                token_id: point_system.token_id,
                new_point,
                timestamp: timestamp::now_seconds(),
            },
        );
    }

    // Get user point
    public fun get_profile_point(user: address): u64 acquires PointSystem {
        assert!(exists<PointSystem>(user), ENFT_NOT_MINTED);
        let point_system = borrow_global_mut<PointSystem>(user);
        point_system.point
    }

    // Get collection info
    public fun get_collection_info(): (String, String, u64, u64, bool) acquires CollectionConfig {
        let collection_config = borrow_global<CollectionConfig>(@admin);
        (
            collection_config.collection_name,
            collection_config.description,
            collection_config.max_supply,
            collection_config.minted_count,
            collection_config.minting_enabled
        )
    }
}