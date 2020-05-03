# rlabp
Protecţie automată a nodului/reţelei împotriva abuzurilor (sau a problemelor tehnice)

## Cum functioneaza?
Logul generat de catre aplicatia SVXLink este citit de catre rlabp.sh si aplica urmatoarele :  
- La mai mult de 5 ptt-uri venite dinspre RF intr-un interval de 20 de secunde,  
aplicatia se restarteaza in modul TX Only timp de 30 de minute.  
- Daca dinspre retea se primesc mai mult de 10 ptt-uri in interval de 30 de secunde, aplicatia opreste traficul dinspre retea catre nod pentru 30 de minute.  

Dupa expirarea timpului, se revine la modul RX/TX.  
  
Instalarea se face simplu :
~~~ \
$git clone https://github.com/yo6nam/rlabp  
$cd rlabp  
$./install.sh  
~~~
  
Modificare fisierului clona de configurare (svxlinknorx.conf) presupune modificarea liniilor din : 
~~~ \
[RxLocal]
...  
SQL_DET=GPIO  
GPIO_SQL_PIN=!gpio20  
...  
~~~
  
in :
~~~ \
[RxLocal]
...  
#SQL_DET=GPIO  
#GPIO_SQL_PIN=!gpio20  
SQL_DET=PTY  
PTY_PATH=/tmp/sql  
...  
~~~
  
Dupa instalare nu este nevoie de alte interventii, scriptul fiind accesat prin cron la fiecare 15 secunde.  
## Trigger extern
Logica de comutare in modul 'TX Only/Operare normala' poate fi comandata si din surse externe, consola, cron, etc.
Argumentul poate fi 0 (Normal), 1 (TX Only) sau 2 (deblocare trafic nod<->reflector)  
~~~
$/opt/rolink/scripts/rlabp.sh 0|1|2
~~~
Aceasta metoda poate fi folosita daca se doreste integrarea cu [phpKontrol](https://github.com/yo6nam/phpKontrol) dar si pastrarea protectiei automata.  
