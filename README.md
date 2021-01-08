Is it time to delete your virtual firewall?
========================================================
### Deploying PAN VM Series firewall with Terraform on Azure

!! Check out the new [Discussion Forum](https://github.com/dustintodd123/azure-terraform-paloaltofw/discussions)
. For general Q&A I prefer the forum to opening issues.

Table of contents
-----------------
[The Cloud Firewall Debate](#The-Cloud-Firewall-Debate)<br/>
[Terraform Plan](#Terraform-plan)<br/>
[Terraform Mechanics](#Terraform-Mechanics)<br/>
[Understanding the VNET topology](#Understanding-the-VNET-topology)<br/>
[PAN Bootstrap notes](#PAN-Bootstrap-notes)<br/>
[Etc](#Etc)<br/>
[References](#References)<br/>
[Q&A](https://github.com/dustintodd123/azure-terraform-paloaltofw/discussions)


The Cloud Firewall Debate 
------------------------------------------------------------------------
#### Cloud native ACL vs. VM Firewall vs. Secure Web Gateway

_(if you want to skip the debate --> [here](#Terraform-plan) )_

Cloud-native network access controls are maturing. Eventually, this debate will be long dead. In the near-term, we are likely to keep using virtual machine based firewalls in public cloud infrastructure. Let's start by reviewing some of the use cases where VM firewalls beat out their cloud-native cousins. 
1. Hybrid deployments in which both premise and public cloud workloads function together in a blended architecture. Typically these deployments will have central management capabilities utilizing shared objects and policies. 
2. Use of access control policies that require the use of dynamically resolved FQDNs, URLs, publicly or privately maintained dynamic IP or URL lists, and applications.
3. VM firewall logging capabilities often includes additional detail not found in cloud-native logging. For instance, PAN VM firewalls logging can extract URLs from HTTP requests and provide application identification.
4. And not to be forgotten, circumstances sometimes force the wholesale migration of brownfield workloads into the cloud with little to no modification. It's an imperfect world. ¯\_(ツ)_/¯

There are pleny of other options including:
- Web proxies either hosted or cloud Secure Web Gateway's (e.g., [Zscaler](https://www.zscaler.com/solutions/web-security))
- Cloud native access policies
- Cloud native firewall services 
- Identity centric architecutre ? (e.g. [Gartner SASE](https://www.gartner.com/doc/reprints?id=1-1ZFQJAP6&ct=200709&st=sb))

### A bit more detail
#### Cloud Native ACL
Pro
- Highest Bandwidth
- Lowest Latency
- Varies by platform, but generally well integrated with cloud workloads (e.g. using dynamic tags to define workload policies)
- All layer 3 protocols supported

Con
- No hybrid capability
- Lack of standard central mgmt capabilities such as shared objects used in multiple rules across many devices
- Typically poor support for FQDN resolution, incorporation of dyanmic address/fqdn/URL lists, granular application specific policies
- While all traffic can be logged, the logging is typically limited to basic source - destination tuples. 

### VM firewall
Pro
- Hybrid deployment supported
- Centralized mgmt tools
- Granuluar policies
- Indepth logging
- Low latency overhead
- All layer 3 protocols supported

Con
- Limited cloud integration, PAN offers a Azure plugin that handles dynamic workload information in policies
- Bandwidth is limited vs. compared to native ACL

### Secure Web Gateway
Pro
- Simplest to manage 
- Hybrid support (by virtue of being offered as SaaS)
- Detailed logging

Con
- Limited to select protocols
- Bandwidth
- Latency
- Cloud integration


In Emoji form:
Attribute | Native ACL | VM Firewall | Secure Web Gateway
:---: | :---: | :---: | :---:
Latency | 		:medal_sports: | :+1: | :raised_eyebrow::raised_eyebrow:
Policy | :raised_eyebrow: | 	:medal_sports: | :+1:
Logging | :+1: | :medal_sports: | :+1:
Throughput | 	:medal_sports:| :+1: | :+1:
Integration | :+1: | :+1: | :raised_eyebrow:


Terraform plan
---------------
At the most basic level, this plan deploys an Azure VNET with a fictional topology (public and private subnets, etc.), along with a single PAN VM series firewall.  The firewall configuration is installed via the PAN [bootstrap]( https://docs.paloaltonetworks.com/vm-series/9-1/vm-series-deployment/bootstrap-the-vm-series-firewall.html) process. The bootstrap process can use either a pre-built firewall configuration stored in a file or using a PAN [Panorama](https://www.paloaltonetworks.com/network-security/panorama) central mgmt server. If you would like to manually configure the firewall, remove the bootstrap parameters from custom_data related to the bootstrap process. 

If you plan to deploy an application architecture that includes a PAN firewall using a CI/CD build process, certainly, you will automate the firewalls device configuration and policy creation. Kudos to Palo Alto for giving developers multiple ways to implement automation. Panorama is a good(ish) tool for automating policy deployment. If you are interested in configuring the PAN firewall via Terraform check out the PANOS resource module for Terraform [here](https://live.paloaltonetworks.com/t5/terraform/ct-p/Terraform). Also, check out the Palo Alto Networks Github [page](https://github.com/PaloAltoNetworks) for examples of other methods including [Ansible](https://www.ansible.com) and [Python](https://www.python.org). 

Terraform Mechanics
-------------------
There are a wide variety of approaches to using Terraform with Azure. When developing a testbed environment, I prefer to use VSCODE w/the Terraform & Azure extensions. In this setup, Terraform execution occurs in the Azure [Cloud Shell](https://docs.microsoft.com/en-us/azure/cloud-shell/overview) service. The Cloud Shell service stores the TF state file on the Azure [Clouddrive](https://docs.microsoft.com/en-us/azure/cloud-shell/persisting-shell-storage) service. Azure Recovery Service can be used to backup the Clouddrive containing the TF state file. VSCODE w/Azure+Terraform instructions are here: [Configure the Azure Terraform Visual Studio Code extension](https://docs.microsoft.com/en-us/azure/developer/terraform/configure-vs-code-extension-for-terraform)

If you are interested in the big picture view as to how to use Terraform to drive to Infrastructure as Code operations read [this](https://www.terraform.io/docs/cloud/guides/recommended-practices/index.html). 

Understanding the VNET topology
-------------------------------
As the diagram depicts, East-West traffic between the public and private subnets, does not use the VM firewall. The VM firewall is positioned to handle North-South traffic between the Internet and the private subnets. An Azure Network Security Group (NSG) is used to control network policy between the private and public subnet. This is not an endorsment of any single architecture. But intended to be a good example that blends together multiple concepts. 

![Read more words!](docs/examplenet1.jpg)

The plan creates a single route table containing only a default route that directs Internet bound traffic to the firewall. I wanted to keep this example easy to understand, but most live environments will be more complicated. It would be normal in a real-world use case to have connections to other private environments using an SD-WAN VM, VM firewall IPSEC tunnels, or the native Azure VPN Gateway. 

The next diagram provides a bit more detail about the mapping between public IPs <-> VNICs <-> PAN interfaces. 

![Read more words!](docs/examplenetv3.jpg)

This bit of TF code within the azurerm_virtual_machine code block controls mapping of VNICs to PAN OS. 
```
 primary_network_interface_id = azurerm_network_interface.FW_VNIC0.id
  network_interface_ids = [azurerm_network_interface.FW_VNIC0.id,
                           azurerm_network_interface.FW_VNIC1.id,
                           azurerm_network_interface.FW_VNIC2.id ]
```
The ordering of the azurerm_network_interface resources in the network_interface_ids assingment controls how they are enumerated in PAN OS.

PAN Bootstrap notes
-------------------
The bootstrap process allows a newly provisioned PAN VM firewall to either load a pre-built firewall configuration or register itself with a Panorama mgmt server and have its device config and policies pushed down to it. The config files needed to initiate the bootstrap process are stored in an Azure storage account. 


Configuring Bootstrap
---------------------
I have provided a pre-built [bootstrap.xml](bootstrap-file-based/bootstrap.xml) firewall config file tailored to this VNET topology, the config file permits all outbound traffic with appropriate logging, threat/URL category blocking, and other system settings configured.  
1. Create a Azure storage account.
2. Create a file share in the new storage account named _bootstrap_.
3. In the _bootstrap_ file share create the following folder structure:

![Read more words!](docs/storageexplorer.PNG)

4. In the _bootstrap-file-based_ repository folder upload the _init-cfg.txt_ and _bootstrap.xml_ file to the _config_ folder in the storage account. 
5. Update the pan.tf file with the correct parameters to allow the PAN VM to authenticate and download the _init-cfg.txt_ and _bootstrap.xml_ file. There are 3 parameters that must be passed to the new VM via the custom_data data block "storage-account", "access-key",  "file-share". This is section of the pan.tf file from the repository:
  ```terraform
    os_profile {
    computer_name  = var.FirewallVmName
    admin_username = "yourusername"
    admin_password = "yourpassword"
    custom_data = join(
      ",",
      [
       "storage-account=<storage account name>",
       "access-key=<storge acct access key>",
       "file-share=bootstrap",
       "share-directory=None"
      ],
    )
  }
  ```
   - storage-account and access-key can be both be retrieved via the Azure portal. Locate the storage account you created and click on the Access Keys menu.
  
  ![Read more words!](docs/accesskey.JPG)
  
  - share-directory is "bootstrap" because that is what suggested it be named in step 2
  
  6. (Optional) The bootstrap _content_ folder can be populated with threat data files. These can be downloaded from the PAN support portal here [Dynamic Updates](https://support.paloaltonetworks.com/Updates/DynamicUpdates/52078). 
  7. (Optional) The example is configured with a pay-as-you-go license (sku=bundle2), a bring-your-own license can be deployed by switching the sku and plan paramter in the pan.tf to "byol". Also the bootstrap _license_ folder must be populated with a _authcodes_ file that contains the authcode for the firewall being deployed. 
  8. The _bootstrap.xml_ file has a default admin username and password configured which should be changed after initial login. See the [Readme](bootstrap-file-based/Readme)

Bootstrap using Panorama
------------------------
If you have a Panorama server already configured and want the firewall to register with it to receive a centrally managed config a couple additional things must be done.
1. Use the _init-cfg.txt_ from the _bootstrap-panorama_ folder. 
2. Before uploading _init-cfg.txt_ edit these 2 parameters.
```
   vm-auth-key=1234567890
   panorama-server=1.1.1.1
```
  - "vm-auth-key" is generated on the Panorama server from the command line using the following [procedure](https://docs.paloaltonetworks.com/vm-series/9-1/vm-series-deployment/bootstrap-the-vm-series-firewall/generate-the-vm-auth-key-on-panorama.html).
  - "panorama" is the public IP address of you Panorama server. (Note: TCP port 3978 and 28443 must be allowed inbound to the Panorama server)
  - A note on two other parameters in the _init-cfg.txt_ file. "tplname" and "dgname" these are the template name and device group name configured in Panorama. This is how you fully automate configuration via Panorama using bootstrap. If you have already created a device template stack and defined device policies you can populate these two fields. 
 3. Update the _init-cfg.txt_ sample file with your auth key and the panorama server IP address, then upload it to the _config_ folder.

Etc
---
1. The pan.tf file has several !!!Change Me!!! variables, make sure to replace with the required values. 
2. The main.tf has a code block at the end that is commented out. It builds a Windows 10 VM, use the bastion host service to remotely access the VM. I use it for testing the completed deployment. 

References
----------
  [Multi-Cloud Security Automation Lab Guide](https://multicloud-automation-lab.readthedocs.io/en/latest/)<br/>
  [PaloAltoNetworks Repository of Terraform Templates](https://github.com/PaloAltoNetworks/terraform-templates)<br/>
  [Terraform Azure](https://www.terraform.io/docs/providers/azurerm/index.html)<br/>
  [Gartner SASE](https://www.gartner.com/doc/reprints?id=1-1ZFQJAP6&ct=200709&st=sb)<br/>
  News from the bleeding edge<br/>
  [Hashicorp Boundary](https://docs.paloaltonetworks.com/vm-series/8-1/vm-series-deployment/set-up-the-vm-series-firewall-on-azure/vm-monitoring-on-azure/azure-vm-monitoring.html#id183KK0E0GL4)<br/>
  [Announcing Consul Terraform Sync Tech Preview](https://www.hashicorp.com/blog/announcing-consul-terraform-sync-tech-preview)<br/>
  [New GKE Dataplane V2 increases security and visibility for containers](https://cloud.google.com/blog/products/containers-kubernetes/bringing-ebpf-and-cilium-to-google-kubernetes-engine)
  
