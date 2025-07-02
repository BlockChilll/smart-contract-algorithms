from moccasin.boa_tools import VyperContract

from src import deposit_decay


def deploy_deposit_decay() -> VyperContract:

    deployed_contract = deposit_decay.deploy()

    print(f"Deployed contract at {deployed_contract.address}")
    return deployed_contract

def moccasin_main() -> VyperContract:
    return deploy_deposit_decay()