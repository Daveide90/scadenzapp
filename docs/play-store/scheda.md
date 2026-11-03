# Scheda di Google Play · ScadenzApp 1.4.0 (beta, test chiuso)

Testi da copiare in Play Console › Crescita › Presenza nello store › Scheda dello store principale. Lingua: italiano (predefinita). I limiti di caratteri sono controllati da `tools/controlla_scheda.py`.

## Nome dell'app (massimo 30 caratteri)

```
ScadenzApp: scadenze farmaci
```

## Descrizione breve (massimo 80 caratteri)

```
Scadenze dei farmaci negli armadietti: lettura della confezione e avvisi
```

## Descrizione completa (massimo 4000 caratteri)

```
ScadenzApp tiene l'inventario delle scadenze dei farmaci negli armadietti: il carrello delle emergenze, l'armadio del reparto, il frigo, l'ambulatorio, oppure l'armadietto di casa. Si inquadra la confezione, si controlla la data e l'app pensa al resto.

LETTURA DELLA CONFEZIONE
La fotocamera legge la data di scadenza stampata, il Data Matrix (scadenza e lotto), il bollino e il codice AIC. Dal codice AIC escono nome, forma e dosaggio, grazie al catalogo AIFA incluso nell'app. Prima di salvare si conferma sempre la data: la confezione fa fede.

ARMADIETTI A COLORI
Quanti armadietti servono, ognuno con i suoi farmaci colorati per scadenza: scaduto, in scadenza, attenzione, a posto. La home mostra per ogni armadietto la scadenza più vicina.

UN AVVISO AL GIORNO
Alle 8 del mattino, un solo avviso con i farmaci che scadono fra 30 giorni, fra 7 giorni o quel giorno. Sulla schermata di blocco i nomi non compaiono.

LISTA DI REINTEGRO
Tutti i farmaci da sostituire di tutti gli armadietti, divisi in tre fasce con soglie scelte da te. Si esporta in PDF, si salva o si manda per email a chi deve ordinarli.

CONTROLLI E REPORT
Registra chi ha controllato quale armadietto e quando, quali scaduti sono stati tolti, con una nota. A fine mese il report in PDF, con lo spazio per la firma.

RICERCA PER LOTTO
Quando viene ritirato un lotto, si scrive il numero e si vede subito in quali armadietti si trova.

I DATI RESTANO SUL TELEFONO
ScadenzApp non ha accesso a Internet: niente account, niente pubblicità, niente statistiche d'uso. Il database è cifrato. Il blocco con impronta o PIN è facoltativo. I backup sono cifrati con una password e si salvano dove vuoi; l'app ricorda quando l'ultimo backup è vecchio.

USO PREVISTO E LIMITI
ScadenzApp è uno strumento di inventario e non è un dispositivo medico: non dà indicazioni su diagnosi, terapie, dosaggi o somministrazioni. La data letta dalla fotocamera può essere sbagliata e va controllata sulla confezione. I dati dei farmaci provengono dagli open data dell'AIFA (Agenzia Italiana del Farmaco, licenza CC BY 4.0) con la data indicata nell'app, e possono non comprendere variazioni successive; l'AIFA non è coinvolta in quest'app. L'app non riceve ritiri di lotti né allerte, e le notifiche dipendono dalle impostazioni del telefono. Report e liste non sostituiscono i registri e le procedure della struttura.

Gratuita, senza pubblicità e senza acquisti.
```

## Note sulla versione per il test chiuso (massimo 500 caratteri)

```
Prima versione di prova su Google Play.
Novità: ricerca per nome o lotto in tutti gli armadietti; backup salvabile fuori dall'app con promemoria; un solo avviso al giorno; PDF con tutte le lettere dei nomi (anche rumene e polacche); date più leggibili; catalogo AIFA aggiornato al 3/11/2026.
Prima di installare questa versione, chi aveva l'app installata a mano: fai un backup, salvalo fuori dall'app, disinstalla, poi installa da Google Play e ripristina.
```

## Grafica

| Elemento | File | Requisiti di Google |
|---|---|---|
| Icona | `grafica/icona_512.png` | 512 × 512, PNG a 32 bit, massimo 1 MB |
| Immagine in evidenza | `grafica/immagine_in_evidenza.png` | 1024 × 500, PNG a 24 bit senza trasparenza |
| Screenshot del telefono | `../schermate/01_armadietti.png` … `05_controlli.png` | da 2 a 8, 9:16, lato da 320 a 3840 px; queste sono 1080 × 1920 |

Ordine consigliato delle schermate: 02 armadietto, 03 reintegro, 01 armadietti, 04 ricerca per lotto, 05 controlli (la prima è quella che si vede nei risultati di ricerca). Le schermate sono generate dai widget veri dell'app con dati inventati, quindi rappresentano l'app com'è; non c'è la schermata della fotocamera, che con dati finti non si può produrre senza simulare la scansione.

## Categoria, contatti, paesi

| Campo | Valore |
|---|---|
| Tipo | App |
| Categoria | Medicina |
| Email di contatto | l'alias dedicato (fase 0.7 del piano), mai l'indirizzo personale |
| Sito web | facoltativo, si può lasciare vuoto |
| Telefono | lasciare vuoto |
| Prezzo | Gratuita. **Attenzione: un'app pubblicata gratis su Google Play non può più diventare a pagamento.** |
| Paesi | solo Italia: catalogo, testi e informativa sono italiani |
