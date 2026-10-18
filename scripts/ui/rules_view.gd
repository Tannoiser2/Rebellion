extends Control
## Regole in breve (riassunto scritto per questa versione digitale) e comandi.

var main

const PAGES := [
	["Lo scopo", """[b]L'Impero Galattico[/b] vince se trova la base ribelle e la conquista: alla fine di un combattimento nel sistema della base non devono restare unità terrestri ribelli e l'Impero deve averne almeno una.

[b]L'Alleanza Ribelle[/b] vince se il segnalino tempo raggiunge il segnalino reputazione. La reputazione parte da 14 e scende completando obiettivi e certe missioni; il tempo sale di 1 a ogni round. Se l'Impero trova la base prima, i Ribelli perdono."""],
	["Il round", """Ogni round ha tre fasi.

[b]1. Assegnazione.[/b] I Ribelli e poi l'Impero assegnano in segreto i leader alle carte missione della mano (1 o 2 leader per carta). I leader non assegnati restano in riserva: serviranno per attivare sistemi o per opporsi alle missioni avversarie.

[b]2. Comando.[/b] A turno, iniziando dai Ribelli, ogni giocatore fa una cosa: rivela una missione assegnata e la risolve (o la tenta), oppure attiva un sistema con un leader della riserva e vi sposta unità dai sistemi adiacenti, oppure passa. Si continua finché passano entrambi.

[b]3. Ripristino.[/b] I leader tornano in riserva, si pescano missioni, l'Impero pesca 2 carte sonda, i Ribelli possono pescare un obiettivo, il tempo avanza. Sulle caselle indicate dalla traccia si recluta un leader, si costruiscono e si schierano unità."""],
	["Missioni", """Le missioni [b]«Risolvi»[/b] riescono da sole. Le missioni [b]«Tenta»[/b] riescono se nessuno si oppone; altrimenti l'avversario può mandare un leader dalla sua riserva nel sistema: ognuno tira tanti dadi quante sono le icone dell'abilità richiesta (diplomazia, intelligence, logistica, operazioni speciali) dei propri leader, e il tentativo riesce con più successi dell'opposizione. Il colpo, il colpo diretto e lo speciale (che vale 2) contano come successi.

Un leader con il ritratto stampato sulla carta aggiunge 2 dadi."""],
	["Movimento e combattimento", """Si attiva un sistema mettendoci un leader con valori tattici. Si possono spostare unità dai sistemi adiacenti che non hanno già un proprio leader. Le unità terrestri e i caccia TIE viaggiano solo sulle navi con capacità di trasporto.

Se nel sistema ci sono unità di tutte e due le fazioni comincia il [b]combattimento[/b]: per ogni round si combatte nello spazio e sulla terra. Si tirano i dadi delle unità (rossi e neri, al massimo 5 per colore), si giocano le carte tattica pescate grazie ai valori tattici dei leader e si assegnano i danni: un colpo va alle unità con salute dello stesso colore del dado, un colpo diretto a qualsiasi unità. Dopo ogni round chi ha attivato il sistema può ritirarsi.

Con L'Ascesa dell'Impero si può scegliere il [b]combattimento cinematografico[/b], con le tattiche avanzate."""],
	["La base ribelle", """I Ribelli scelgono in segreto il sistema della base e mettono unità nella casella Base Ribelle del tabellone: da lì possono uscire verso il sistema della base e quelli adiacenti. L'Impero esclude sistemi con le carte sonda e con le missioni. Quando la flotta imperiale arriva nel sistema della base, la base viene rivelata.

Sottomettere: un sistema popolato con unità terrestri imperiali e senza fedeltà imperiale è sottomesso. Un sistema imperiale (fedele o sottomesso) produce unità imperiali durante la costruzione."""],
	["Comandi", """[b]Tabellone:[/b] trascina per ruotare, rotella o pizzico per lo zoom, tasto destro (o Maiusc+trascina) per spostare la visuale, doppio clic per rimetterla a posto. Il pulsante 2D mostra la galassia dall'alto.

[b]Scelte:[/b] i sistemi da scegliere si illuminano; si clicca il sistema o il suo nome nel pannello in basso. Il pulsante «Scelta automatica» lascia decidere all'IA.

[b]Carte:[/b] passa con il mouse su una carta per ingrandirla con il testo in italiano accanto. Le carte dell'Ascesa dell'Impero hanno l'immagine originale inglese e la traduzione a fianco.

[b]In due sullo stesso dispositivo:[/b] fra un turno e l'altro una schermata nasconde le carte e la base: passatevi il dispositivo.

[b]F11[/b] schermo intero."""],
]

var idx := 0
var body: RichTextLabel
var title_lbl: Label
var tab_btns: Array = []


func _ready() -> void:
	size = Vector2(1920, 1080)
	var t := UI.title("Regole in breve", 46, UI.HOLO)
	t.position = Vector2(80, 40)
	add_child(t)
	var tabs := VBoxContainer.new()
	tabs.add_theme_constant_override("separation", 10)
	tabs.position = Vector2(80, 140)
	add_child(tabs)
	for i in PAGES.size():
		var b := UI.button(PAGES[i][0], 380, 58, 21)
		var i2 := i
		b.pressed.connect(func():
			idx = i2
			_show())
		tabs.add_child(b)
		tab_btns.append(b)
	var back := UI.primary(UI.button("Torna al menu", 380, 64, 24))
	back.pressed.connect(func(): main.show_menu())
	tabs.add_child(back)
	var p := UI.panel(30)
	p.position = Vector2(520, 140)
	p.custom_minimum_size = Vector2(1300, 860)
	p.size = Vector2(1300, 860)
	add_child(p)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	p.add_child(vb)
	title_lbl = UI.title("", 34, UI.GOLD)
	vb.add_child(title_lbl)
	body = RichTextLabel.new()
	body.bbcode_enabled = true
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.custom_minimum_size = Vector2(1220, 740)
	body.add_theme_font_size_override("normal_font_size", 23)
	body.add_theme_font_size_override("bold_font_size", 23)
	vb.add_child(body)
	_show()


func _show() -> void:
	title_lbl.text = PAGES[idx][0]
	body.text = PAGES[idx][1]
	for i in tab_btns.size():
		UI.tint(tab_btns[i], UI.HOLO if i == idx else UI.STEEL_L)
