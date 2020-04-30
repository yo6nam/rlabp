# rlabp
Protecţie automată a nodului/reţelei împotriva abuzurilor (sau a problemelor tehnice)

## Cum functioneaza?
La mai mult de 5 ptt-uri (se poate defini limita in rlabp.sh) venite dinspre RF intr-un interval de 20 de secunde,  
aplicatia se restarteaza in modul TX Only timp de 30 de minute.  
Daca dinspre retea se primesc mai mult de 10 ptt-uri, aplicatia opreste traficul dinspre  
retea catre nod.  
Dupa expirarea timpului, se revine la modul RX/TX.
  
Instalarea se face simplu :
~~~ \
$git clone https://github.com/yo6nam/rlabp  
$cd rlabp  
$./install.sh  
~~~
  
Modificare fisierului clona de configurare presupune modificarea liniilor din : 
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
