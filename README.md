OdoCrypt FPGA Miner
===================

Requirements
------------

Currently only supports Intel (Altera) FPGAs on Linux hosts.

Installing Quartus Prime
------------------------

Quartus Prime is required to both compile and run this miner.  It is currently available at
<https://fpgasoftware.intel.com/> .  To figure out what edition you need, check the device
support list.  To minimize your download, choose the Individual Files tab, then download only
Quartus Prime, and the device support files for the devices you're using.  Install according
to the instructions on their website.

After installing, set the variable ``QUARTUSPATH`` to point to the ``quartus/bin`` directory of
your installation.  For example ``export QUARTUSPATH="/home/miner/altera/18.1/quartus/bin"`` .
This line should be added to your ``~/.profile`` file or another file that is sourced whenever a
shell is launched.  Don't forget to source the file after editing it.

Solo Mining
-----------

Install and start a full node via <https://github.com/digibyte/digibyte>.

* A python interpreter is required and pip is recommended - ``apt install python python-pip`` (Python 3 should also work, but most testing has been done in Python 2).
* Python modules base58 and requests - ``pip install base58 requests``

Additional Files
----------------

You need to install a custom udev rule in order to allow a non-root user access to FPGA hardware.

* Open ``99-altera.rules``, and change the ``1000`` on the last line to your user id.  Alternatively, run ``sed -i s/1000/$(whoami)/ 99-altera.rules`` (don't run this command as root).
* Run ``sudo cp 99-altera.rules /etc/udev/rules.d/``
* Run ``sudo udevadm control --reload``

Connecting Your Hardware
------------------------

Notice: It is highly recommended that you remove the acrylic cover on your development kit (if it comes with one) to prevent it from overheating.

* Connect one end of your development kit's USB cable to your computer, and the other end to the development kit.  If your development kit has multiple USB ports, be sure to connect to the one labelled "USB Blaster".
* Connect your development kit's power cable, and turn on the device.
* Verify the presence of your device by running ``lsusb | grep Altera`` (this should output one line per development kit).
* Further verify your setup by running ``$QUARTUSPATH/jtagconfig`` (this will list all of your recognised development kits).

Starting to Mine
----------------

This will require multiple terminal windows.  A screen multiplexer such as [tmux](https://github.com/tmux/tmux/wiki) or [screen](https://www.gnu.org/software/screen/) may make things easier for you.

* Ensure your DigiByte node is running.  It is recommended that you do not specify an rpcpassword in digibyte.conf.  The rpcuser and rpcpassword options will soon be deprecated.
* In one terminal, go to the ``src`` directory and run ``./autocompile.sh --testnet cyclone_v_gx_starter_kit de10_nano``
* In another terminal, go to the ``src/pool/solo`` directory and run ``python pool.py --testnet <dgb_address>``
* Finally, for each mining fpga open a terminal in the ``src/miner`` directory and run ``$QUARTUSPATH/quartus_stp -t mine.tcl [hardware_name]``.  The ``hardware_name`` argument is optional, and if not specified the script will prompt you to select one of the detected mining devices.  If you're comfortable using [screen](https://www.gnu.org/software/screen/), you can run ``src/miner/mine_in_screen.sh`` instead to start a screen session with one window per mining device.

