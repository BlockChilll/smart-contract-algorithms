import boa

WEEK: int = int(604800)
YEAR: int = 365 * 86400  # 1 year

def test_contract_deploy(deposit_decay_contract):
    assert deposit_decay_contract.address is not None

def test_checkpoint(deposit_decay_contract, alice, bob):
    AMOUNT: int = int(100e18)
    END: int = boa.env.timestamp + 4 * YEAR

    deposit_decay_contract.checkpoint(alice, (0, 0), (AMOUNT, END))
    alice_bal = deposit_decay_contract.balanceOf(alice)
    assert (alice_bal // 1e18) * 1e18 == (AMOUNT * 99 // 100 // 1e18) * 1e18 # truncation loses 1% of deposited amount
    print(alice_bal)

    deposit_decay_contract.checkpoint(bob, (0, 0), (AMOUNT, END))
    bob_bal = deposit_decay_contract.balanceOf(bob)
    assert (bob_bal // 1e18) * 1e18 == (AMOUNT * 99 // 100 // 1e18) * 1e18 # truncation loses 1% of deposited amount
    print(bob_bal)

    supply = deposit_decay_contract.totalSupply()
    assert supply == bob_bal + alice_bal

    boa.env.time_travel(2*YEAR) # 2 years passed

    alice_bal2 = deposit_decay_contract.balanceOf(alice)
    assert alice_bal2 // 1e18 * 1e18 == alice_bal // 2 // 1e18 * 1e18    # truncation loses 1% of deposited amount

    bob_bal2 = deposit_decay_contract.balanceOf(bob)
    assert bob_bal2 // 1e18 * 1e18 == bob_bal // 2 // 1e18 * 1e18    # truncation loses 1% of deposited amount

    supply2 = deposit_decay_contract.totalSupply()
    assert supply2 // 1e18 * 1e18 == supply // 2 // 1e18 * 1e18

    AMOUNT2: int = int(200e18) # double the amount
    END2: int = boa.env.timestamp + 2 * YEAR # same end as before

    deposit_decay_contract.checkpoint(alice, (AMOUNT, END), (AMOUNT2, END2))

    bob_bal3 = deposit_decay_contract.balanceOf(bob)
    assert bob_bal2 == bob_bal3
    alice_bal3 = deposit_decay_contract.balanceOf(alice)  # doubles the balance
    assert alice_bal2 * 2 // 1e18 * 1e18 == alice_bal3 // 1e18 * 1e18

    boa.env.time_travel(YEAR) # 3 years passed

    bob_bal4 = deposit_decay_contract.balanceOf(bob)
    assert bob_bal4 // 1e18 * 1e18 == bob_bal3 // 2 // 1e18 * 1e18 
    print(bob_bal4)
    alice_bal4 = deposit_decay_contract.balanceOf(alice)
    assert alice_bal4 // 1e18 * 1e18 == alice_bal3 // 2 // 1e18 * 1e18
    print(alice_bal4)

    supply3 = deposit_decay_contract.totalSupply()
    assert (supply3 // 1e19 * 1e19) == (alice_bal4 + bob_bal4) // 1e19 * 1e19

    boa.env.time_travel(YEAR) # 4 years passed

    bob_bal5 = deposit_decay_contract.balanceOf(bob)
    assert bob_bal5 == 0

    alice_bal5 = deposit_decay_contract.balanceOf(alice)
    assert alice_bal5 == 0

    supply4 = deposit_decay_contract.totalSupply()
    assert supply4 == 0
