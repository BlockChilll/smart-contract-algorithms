import boa
import pytest
from eth_account import Account
from eth_utils import to_wei
from moccasin.boa_tools import VyperContract
from moccasin.config import get_active_network

BALANCE = to_wei(1000, "ether")

@pytest.fixture(scope="session")
def active_network():
    return get_active_network()

@pytest.fixture(scope="function")
def alice():
    entropy = 13
    account = Account.create(entropy)
    boa.env.set_balance(account.address, BALANCE)
    return account.address

@pytest.fixture(scope="function")
def bob():
    entropy = 13
    account = Account.create(entropy)
    boa.env.set_balance(account.address, BALANCE)
    return account.address

@pytest.fixture(scope="function")
def reward_contract(active_network, alice) -> VyperContract:
    with boa.env.prank(alice):
        return active_network.manifest_named("reward_accumulation")