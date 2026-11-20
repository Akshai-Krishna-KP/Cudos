Track C GPU appliance - boot this stick on a UEFI PC with an NVIDIA GPU (Secure Boot off).

Optional settings: put files in the "trackc" folder on THIS partition (works from Windows):
  trackc/authorized_keys   your SSH public key  -> SSH on, key-only, user "gpu"
  trackc/wifi.txt          two lines:  SSID=YourNetwork   PASSWORD=YourPassword
Wired Ethernet works without any file. On screen you are logged in as "gpu":
  cd ~/cuda/examples && cuda-dev make && cuda-dev ./matmul 2048
