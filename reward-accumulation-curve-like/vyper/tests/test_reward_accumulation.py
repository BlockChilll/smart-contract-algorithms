import boa

WEEK: int = int(604800)

def test_contract_deploy(reward_contract):
    assert reward_contract.address is not None


def test_rate(reward_contract):
    rate: int = reward_contract.get_rate()
    assert rate == int(1e18)


def test_weight(reward_contract):
    weight: int = reward_contract.get_weight()
    assert weight == int(5e17)
    

def test_update_working_balance_max(reward_contract, alice):
    USER_LP_BALANCE: int = int(10e18)
    TOTAL_LP_BALANCE: int = int(100e18)
    USER_BOOST_BALANCE: int = int(10e18)
    TOTAL_BOOST_BALANCE: int = int(100e18)

    with boa.env.prank(alice):
        reward_contract.update_working_balance(alice, USER_LP_BALANCE, TOTAL_LP_BALANCE, USER_BOOST_BALANCE, TOTAL_BOOST_BALANCE)

    user_wb: int = reward_contract.get_user_wb(alice)
    assert user_wb == USER_LP_BALANCE

    working_supply: int = reward_contract.get_working_supply()
    assert working_supply == USER_LP_BALANCE


def test_update_working_balance_min(reward_contract, alice):
    USER_LP_BALANCE: int = int(10e18)
    TOTAL_LP_BALANCE: int = int(100e18)
    USER_BOOST_BALANCE: int = int(0)
    TOTAL_BOOST_BALANCE: int = int(100e18)

    with boa.env.prank(alice):
        reward_contract.update_working_balance(alice, USER_LP_BALANCE, TOTAL_LP_BALANCE, USER_BOOST_BALANCE, TOTAL_BOOST_BALANCE)

    user_wb: int = reward_contract.get_user_wb(alice)
    assert user_wb == USER_LP_BALANCE * 40 // 100

    working_supply: int = reward_contract.get_working_supply()
    assert working_supply == USER_LP_BALANCE * 40 // 100


def test_checkpoint(reward_contract, alice, bob):
    invest_lp_token_max_boost_alice(reward_contract, alice)
    alice_r1 = reward_contract.get_user_reward(alice)
    assert alice_r1 == 0
    reward_contract.checkpoint(alice)
    alice_r2 = reward_contract.get_user_reward(alice)
    assert alice_r2 == 0

    boa.env.time_travel(WEEK)

    reward_contract.checkpoint(alice)
    # rate * weight * dt * _working_balance // working_supply    1e18 * 5e17 * 604800 * 10e18 // 10e18 * 1e18 = 302400000000000000000000
    alice_r3 = reward_contract.get_user_reward(alice)
    assert alice_r3 > 0
    assert alice_r3 == 302400000000000000000000

    reward_contract.checkpoint(bob)
    invest_lp_token_max_boost_bob(reward_contract, bob)

    boa.env.time_travel(2*WEEK)
    # 30240000000000000000000 + rate * weight * dt * _working_balance // working_supply   30240000000000000000000 + 1e18 * 5e17 * 604800 * 10e18 // 20e18 * 1e18 = 30240000000000000000000 + 15120000000000000000000
    # 1st iter: 302400000000000000000000 + 10e18 * 15120000000000000000000 = 453600000000000000000000
    # 2st iter: 453600000000000000000000 + 10e18 * 15120000000000000000000 = 604800000000000000000000

    reward_contract.checkpoint(alice)

    # rate * weight * dt * _working_balance // working_supply   1e18 * 5e17 * 604800 * 10e18 // 20e18 * 1e18 = 15120000000000000000000
    # 1st iter: 10e18 * 15120000000000000000000 = 151200000000000000000000
    # 2st iter: 151200000000000000000000 + 10e18 * 15120000000000000000000 = 302400000000000000000000
    reward_contract.checkpoint(bob)

    alice_r4 = reward_contract.get_user_reward(alice)
    assert alice_r4 == 604800000000000000000000

    bob_r1 = reward_contract.get_user_reward(bob)
    assert bob_r1 == 302400000000000000000000
    



# ------------------------------------------------------------------
#                      UTIL FUNCTIONS
# ------------------------------------------------------------------

def invest_lp_token_max_boost_alice(reward_contract, alice):
    USER_LP_BALANCE: int = int(10e18)
    TOTAL_LP_BALANCE: int = int(100e18)
    USER_BOOST_BALANCE: int = int(10e18)
    TOTAL_BOOST_BALANCE: int = int(100e18)

    with boa.env.prank(alice):
        reward_contract.update_working_balance(alice, USER_LP_BALANCE, TOTAL_LP_BALANCE, USER_BOOST_BALANCE, TOTAL_BOOST_BALANCE)

def invest_lp_token_max_boost_bob(reward_contract, bob):
    USER_LP_BALANCE: int = int(10e18)
    TOTAL_LP_BALANCE: int = int(100e18)
    USER_BOOST_BALANCE: int = int(10e18)
    TOTAL_BOOST_BALANCE: int = int(100e18)

    with boa.env.prank(bob):
        reward_contract.update_working_balance(bob, USER_LP_BALANCE, TOTAL_LP_BALANCE, USER_BOOST_BALANCE, TOTAL_BOOST_BALANCE)

def invest_lp_token_min_boost_alice(reward_contract, alice):
    USER_LP_BALANCE: int = int(10e18)
    TOTAL_LP_BALANCE: int = int(100e18)
    USER_BOOST_BALANCE: int = int(0)
    TOTAL_BOOST_BALANCE: int = int(100e18)

    with boa.env.prank(alice):
        reward_contract.update_working_balance(alice, USER_LP_BALANCE, TOTAL_LP_BALANCE, USER_BOOST_BALANCE, TOTAL_BOOST_BALANCE)

def invest_lp_token_min_boost_bob(reward_contract, bob):
    USER_LP_BALANCE: int = int(10e18)
    TOTAL_LP_BALANCE: int = int(100e18)
    USER_BOOST_BALANCE: int = int(0)
    TOTAL_BOOST_BALANCE: int = int(100e18)

    with boa.env.prank(bob):
        reward_contract.update_working_balance(bob, USER_LP_BALANCE, TOTAL_LP_BALANCE, USER_BOOST_BALANCE, TOTAL_BOOST_BALANCE)
