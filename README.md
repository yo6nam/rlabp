# RoLink Abuse Protection (rlabp)
Protecţie automată a nodului/reţelei împotriva abuzurilor (sau a problemelor tehnice)

## Cum functioneaza?
Logul generat de catre aplicatia SVXLink este interpretat de catre scriptul rlabp.sh,\
care ruleaza ca serviciu monitorizand urmatoarele :  
- La mai mult de 4 ptt-uri primite din eter intr-un interval de 20 de secunde,  
aplicatia comuta SVXLink in modul TX Only timp de 1 minut. Daca in interval de 60 de minute se repeta incidentul, timpul de penalizare creste cu cate 5 minute (1min -> 5min -> 10min etc)  
- Daca dinspre retea se primesc mai mult de 10 ptt-uri in interval de 40 de secunde, aplicatia opreste traficul dinspre retea catre nod pentru acelasi interval de timp, mentionat mai sus.

Dupa expirarea timpului, se revine la modul RX/TX.
  
Instalarea se face simplu :
~~~ \
$git clone https://github.com/yo6nam/rlabp  
$cd rlabp  
$./install.sh  
~~~
 
Modificare fisierului de configurare (svxlink.conf) si adaugarea sectiunii de voter, presupune modificarea liniilor din : 
~~~ \
[SimplexLogic]
...
RX=RxLocal
...  
~~~
  
in :
~~~ \
[SimplexLogic]
...
RX=LocalVoter
...
~~~ 

si adaugarea sectiunii (daca nu exista), de preferat deasupra liniei [RxLocal] :
~~~ \
[LocalVoter]
TYPE=Voter
RECEIVERS=RxLocal
VOTING_DELAY=100
BUFFER_LENGTH=100
COMMAND_PTY=/tmp/voter
~~~ 
  
Dupa instalare nu este nevoie de alte interventii, scriptul fiind instalat ca serviciu. Statusul lui poate fi verificat prin comanda
~~~
$systemctl status rlabp
~~~
## Detecţie alternativă (RECOMANDAT!)
Pentru a detecta abuzurile care nu respectă un tipar de timp, se poate modifica fişierul Logic.tcl  
Codul care trebuie adaugat se poate extrage din link-ul [Logic.tcl - Diff / RLAbP](https://www.diffchecker.com/om0isE1M)

Notă : Pentru ca detecţia să devină activă, este necesară modificarea variabilei RGR_SOUND_ALWAYS din svxlink.conf  
RGR_SOUND_ALWAYS=1

## Ce optiuni pot schimba?
Majoritatea variabilelor sunt disponibile pentru modificare in primele linii ale scriptului.\
Dupa ajustarea acestora, este nevoie de restartarea serviciului, folosind 
~~~
$systemctl restart rlabp
~~~

## Trigger extern
Logica de comutare in modul 'TX Only/Operare normala' poate fi comandata si din surse externe, consola, cron, etc.
Argumentul poate fi 0 (Normal), 1 (TX Only), 2 (deblocare trafic nod<->reflector), 3 (blocare trafic nod<->reflector), 9 (reboot) si s (service mode / cerere conectare VPN catre server)
~~~
$/opt/rolink/scripts/rlabp.sh 0|1|2|3|9|s
~~~
Aceasta metoda poate fi folosita daca se doreste integrarea cu [phpKontrol](https://github.com/yo6nam/phpKontrol) pastrand in acelasi timp protectie automata.
