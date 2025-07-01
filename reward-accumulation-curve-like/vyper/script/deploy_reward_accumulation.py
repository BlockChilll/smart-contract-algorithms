from moccasin.boa_tools import VyperContract

from src import reward_accumulation


def deploy_reward_accumulation() -> VyperContract:

    # rate is 1, weight is 0.5
    deployed_contract = reward_accumulation.deploy(int(1e18), int(5e17))

    print(f"Deployed contract at {deployed_contract.address}")
    return deployed_contract

def moccasin_main() -> VyperContract:
    return deploy_reward_accumulation()