' Обязательное объявление переменных включено
Option Explicit

'******************************************
' 
' Main Program
' 
'****************************************** 

'Подавление ошибок
'On Error Resume Next
'Объект файловой системы
Dim objFSO
Set objFSO = CreateObject("Scripting.FileSystemObject")
Dim objTextWriter, objTextReader

'Имя файла, откуда читать данные
Const FileNameWithParams = "Exposure_list.txt"

'Файл для чтения выдержек
Set objTextReader = objFSO.OpenTextFile("Exposure_list.txt", 1, False)
Dim Dictionary_of_exposures						'Словарь выдержек
Set Dictionary_of_exposures = CreateObject("Scripting.Dictionary")
Dim i,n,k,min
Dim SaveLocale : SaveLocale = GetLocale()		'Создаём переменную, которая будет хранить язык, установленный при обработке числовых значений
SetLocale("en-us")								'И устанавливаем его на английский, чтобы разделителем была точка, а не запятая

'Параметры, если требуется перевод из CFA в RGB
Dim Camera_model, Start_prefix, Rgbbalance, Chroma
Camera_model = "450D" : Start_prefix = "w" : Rgbbalance = "rgbbalance 1.4 1 1.4" : Chroma = "18"

'Чтение выдержек (и определение числа файлов) в словарь
If MsgBox ("Вы ввели экспозиции в секундах?"  & vbCr & vbCr & "Нет — подразумевает, что введены только знаменатели." , _
	vbYesNo + vbDefaultButton1, "Ввод параметров") = vbNo Then
	Do
		With Dictionary_of_exposures
			.Add .Count, 1/Eval(objTextReader.ReadLine())
		End With
	Loop Until objTextReader.AtEndOfStream
Else
	Do
		With Dictionary_of_exposures
			.Add .Count, Eval(objTextReader.ReadLine())
		End With
	Loop Until objTextReader.AtEndOfStream
End If

'Сортировка словаря по убыванию выдержек
For i = 0 to UBound(Dictionary_of_exposures.Items())
	Dim temp1, temp2 : temp2 = 0
	k = 0
	Do Until k >= UBound(Dictionary_of_exposures.Items()) - i
		k = k + 1
		If Dictionary_of_exposures.Items()(temp2) < Dictionary_of_exposures.Items()(k) Then		'Сравнение элементов словаря
			temp2 = k
		End If
	Loop
	temp2 = Dictionary_of_exposures.Keys()(temp2)
	temp1 = Dictionary_of_exposures.Item(temp2)
	Dictionary_of_exposures.Remove(temp2)														'Удаление максимального (знак "<") элемента
	Dictionary_of_exposures.Add temp2 , temp1													'И перенос его в конец списка
Next

Set objTextWriter = objFSO.OpenTextFile("HDR_master2.pgm", 2, True)
If MsgBox ("Необходима ли проявка из CFA в RGB?" , vbYesNo + vbDefaultButton2, "Ввод параметров") = vbYes Then
	Start_prefix = "q"
	For i = 0 To UBound(Dictionary_of_exposures.Items())
		objTextWriter.WriteLine("run convert_" & Camera_model & " q" & i+1)
		objTextWriter.WriteLine(Rgbbalance)
		objTextWriter.WriteLine("run chroma_" & Camera_model & "_" & Chroma & "mm")
		objTextWriter.WriteLine("save w" & i + 1)
	Next
End If

'Задаём нужные параметры и объявляем необходимые переменные
k=InputBox("Введите число кадров. Префикс входящей серии — w.", "Ввод параметров", UBound(Dictionary_of_exposures.Items())+1) - 1
n=InputBox("Введите номер кадра без пересветов" & vbCrLf & "0 — Доверить скрипту выбрать кадр с минимальной выдержкой", "Ввод параметров", 0) - 1
min=InputBox("Введите минимальное значение в самом ярком кадре", "Ввод параметров", 0) + 1

'Определение минимальной и максимальной выдержки
Dim shortest, longest : longest = Dictionary_of_exposures.Items()(0)
If n = -1 Then 
	shortest = Dictionary_of_exposures.Items()(UBound(Dictionary_of_exposures.Items()))
Else
	shortest = Dictionary_of_exposures.Item(n)
End If

'Вычисление константы логарифмирования
Dim l : l = Round(32767/(1+log(longest/shortest/min)/log(32767)),0)

'Запись процесса логарифмирования
'На случай, если на каких-то изображениях нет белого пикселя — надо добавить
If MsgBox ("Хотите ли вы добавить белый пиксель в углу?", vbYesNo, "Подготовка к калибровке") = vbYes Then
	objTextWriter.WriteLine("load w" & 1)
	objTextWriter.WriteLine("split_rgb put put put")
	objTextWriter.WriteLine("fill 0")
	objTextWriter.WriteLine("put 1 1 32767")
	objTextWriter.WriteLine("save put")
	objTextWriter.WriteLine("trichro put put put")
	objTextWriter.WriteLine("save put")
	For i = 0 To k
		objTextWriter.WriteLine("load w" & i + 1)
		objTextWriter.WriteLine("add put")
		objTextWriter.WriteLine("save w" & i + 1)
	Next
End If

'Логарифимирование и приведение изображений к единому уровню яркости
For i = 0 To k
	objTextWriter.WriteLine("load w" & Dictionary_of_exposures.Keys()(i) + 1)
	objTextWriter.WriteLine("log " & l)
	objTextWriter.WriteLine("offset " & Round(l * log(longest/(Dictionary_of_exposures.Items()(i))/min)/log(32767) ,0) )
	objTextWriter.WriteLine("clipmin 0 0")
	objTextWriter.WriteLine("save g" & Dictionary_of_exposures.Keys()(i) + 1)
Next

' Выбор, складывать ли полученные изображения или нет
If MsgBox ("Хотите ли вы выполнить сложение полученных файлов?", vbYesNo, "Сложение") = vbNo Then
	MsgBox ("Результат записан в файл HDR_calibration.pgm")
	WScript.Quit
Else
	Const x	= 8192			'начало границы смешивания
	Dim cheat
	cheat = InputBox("Насколько ослабить вклад коротких экспозиций?" 	& vbCrLf & vbCrLf & vbCrLf & _
	"0 — адаптивное сложение исходя только из экспозиций" 				& vbCrLf & vbCrLf & _
	"1 — оптимальное значение, подходящее для большинства ситуаций" 	& vbCrLf & vbCrLf & _
	"20 — нет адаптивного сложения, все сигналы ниже границы смешивания отбрасываются" , "Параметры сложения", "1")
	ReDim adapt_array(k)	'создание массива отношений выдержек в т.ч. для коэффициентов адаптивного сложения
	ReDim bound_array(k)	'создание массива пересчитаных границ смешения кадров
	ReDim I_max_array(k)	'создание массива максимальных значений в соответствующем кадре
	ReDim cheat_array(k)	'создание массива для ослабления вклада коротких экспозиций (из-за возрастающего вклада шума считывания)
	For i = 0 To k
		adapt_array(i) = longest/(Dictionary_of_exposures.Items()(i))
		bound_array(i) = l * log(x*adapt_array(i)/min)/log(32767)
		I_max_array(i) = l * log(32767*adapt_array(i)/min)/log(32767)
		cheat_array(i) = Round((log(adapt_array(i))/log(2)+0.95)^(log(adapt_array(i))/log(2)/(2.4/(cheat+1.0E-19))) ,2)
	Next
	
	' Открываем для записи второй файл. Если нужно.
	'Set objTextWriter = objFSO.OpenTextFile("HDR_addition.pgm", 2, True)
	objTextWriter.WriteLine("load g" & Dictionary_of_exposures.Keys()(0) + 1)
	objTextWriter.WriteLine("save z1")
	For i = 0 To k - 1
		objTextWriter.WriteLine("load z1")
		objTextWriter.WriteLine("offset "& -Round( bound_array(i) ,0 ) )
		objTextWriter.WriteLine("clipmin 0 0")					'обрезание нижней границы для формирования затухания
		objTextWriter.WriteLine("save n1")						'следующий шаг завершит формирование параболического затухания сигнала нижнего кадра
		objTextWriter.WriteLine("prod n1 " & 1/(2*( bound_array(i) - I_max_array(i)  ))  )
		objTextWriter.WriteLine("add z1")						'нижний кадр сформирован. следующий шаг умножит на весовой коэффициент для оптимального сложения
		objTextWriter.WriteLine("mult " & Round(  adapt_array(i+1)*cheat_array(i+1)/(adapt_array(i+1)*cheat_array(i+1)+1),5)  )
		objTextWriter.WriteLine("save z1")						'нижний кадр готов к сумированию с верхним кадром
		objTextWriter.WriteLine("load g" & Dictionary_of_exposures.Keys()(i+1) +1 )					'загрузка нижнего кадра
		objTextWriter.WriteLine("offset "& -Round( bound_array(i) ,0 ) )
		objTextWriter.WriteLine("clipmin 0 0")					'обрезание нижней границы нижнего кадра
		objTextWriter.WriteLine("save n1")						'формирование параболического нарастания сигнала
		objTextWriter.WriteLine("prod n1 " & 1/(2*( I_max_array(i) - bound_array(i)  )))
		objTextWriter.WriteLine("clipmax " & Round(( I_max_array(i) - bound_array(i) )/2,0) & " " & Round(( I_max_array(i) - bound_array(i) )/2,0))
		objTextWriter.WriteLine("save n1")						'предыдущий шаг выполнил обрезку той части, которая должна остаться линейной и мы сохранили параболический кусок
		objTextWriter.WriteLine("load g" & Dictionary_of_exposures.Keys()(i+1) +1 )
		objTextWriter.WriteLine("offset " & -Round( I_max_array(i) ,0))
		objTextWriter.WriteLine("clipmin 0 0")					'обрезание сигнала по границе нижнего кадра, где получилось переполнение
		objTextWriter.WriteLine("add n1")						'добавление нарастающего параболического куска от верхнего кадра
		objTextWriter.WriteLine("mult " & Round( adapt_array(i+1)*cheat_array(i+1)/(adapt_array(i+1)*cheat_array(i+1)+1),5) )
		objTextWriter.WriteLine("save n1")						'умножили на весовой коэффициент как для нижнего изображения, чтобы потом для нарастающей части его сложить со второй половиной
		objTextWriter.WriteLine("load g" & Dictionary_of_exposures.Keys()(i+1) +1 )					'загрузили верхнее изображение
		objTextWriter.WriteLine("mult " & Round(1/(adapt_array(i+1)*cheat_array(i+1)+1),5) )		'умножили его на второй весовой коэффициент
		objTextWriter.WriteLine("add n1")						'и добавили к итогу. Теперь нижний линейный кусок сложится с весом, а оставшаяся часть ляжет сверху, как недостающая часть пирамиды
		objTextWriter.WriteLine("add z1")
		objTextWriter.WriteLine("save z1")
	Next
' Закрываем файл
	objTextWriter.Close()
	' Уничтожение объекта и закрытие второго файла
End if
SetLocale(SaveLocale)
Set objTextWriter = Nothing
Set objFSO = Nothing
