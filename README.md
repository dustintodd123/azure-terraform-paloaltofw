# Deploying PAN VM Series firewall with Terraform on Azure
## Bonus! Panorama Bootstrap via Terraform

You might be asking, why do we need virtual firewall in the public cloud? Specifically in the case of Azure you might ask, I have Network Security Groups and native logging why do I need a virtual firewall? There are couple possible use cases.
1. A hybrid enterprise with both physical and virtual assests, with centrally managed access control policies.
2. Virtual workloads that have complex policies that require permissionming via FQDN, URL, publicly or privately maintained lists of IPs or URLs, Automatic applicaiton identification.
3. Cloud provided network activity logging is insufficient. In the case of PAN VM firewalls the logging can extract URLs from HTTP requests and provide application visibility. 
4. And importantly - occasionaly circumstances force you to shove brownfield workloads into the cloud. It's an imperfect world. 

All that said, deploying a virtual firewall to control network policy is not the only way to solve these problem problems in the cloud. You can, and others wil,l solve these problems in different ways. Some examples of other methods. 
- Web proxies either hosted or cloud based (e.g. Zscaler)
- Automation tools to orchestrate native cloud tools.
- Cloud native access rules
### Table of content
[Understanding the VNET topology](#Understanding-the-VNET-topology)

### What does this Terraform plan deploy?
At the most basic level this plan deploys a Azure VNET with ficitonal topology (public and private subnets, etc), along with a single PAN VM series firewall that is provisioned via the PAN [bootstrap]( https://docs.paloaltonetworks.com/vm-series/9-1/vm-series-deployment/bootstrap-the-vm-series-firewall.html) process using a PAN [Panorama](https://www.paloaltonetworks.com/network-security/panorama) central mgmt server. This example can be used without the bootstrap process and Panorama. But exactly no one wants to manage cloud firewalls individually, well at least I don't. All the details of how to automate deployment of configs and polciies via Panorama is beyond the scope of this document. 

### Understanding the VNET topology
A close reading of this will reveal that the "public" subnet, where a VM hosting a Internet accessible workload would be positioned, is not on a leg of the virtual firewall. Good catch. I kept this segment access control to be handled by a Azure Network Security Group (NSG). East-West communication between hosts in a app architecture will not benefit as much from access controls provided by a modern VM firewall. Also it was good opportunity to combined multiple concepts in one example.  
![Read more words!](docs/examplenet1.jpg)

A bit more detail about the specific of the way Azure public IPs and VNICs map to PAN interfaces.

![Read more words!](docs/examplenetv3.jpg)
