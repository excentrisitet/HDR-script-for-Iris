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
	
	' Имя файла, откуда читать данные
	Const FileNameWithParams = "Exposure_list.txt"

	'Задаём нужные параметры и объявляем необходимые переменные
	Dim i,n,k,min
		k=InputBox("Введите число кадров. Префикс входящей серии — w.")
		n=InputBox("Введите номер первого кадра без пересветов")
		min=InputBox("Введите минимальное значение в самом ярком кадре")+1	
	
	' Файл для чтения выдержек
	Set objTextReader = objFSO.OpenTextFile("Exposure_list.txt", 1, False)
	
	'Создание списка выдержек
	ReDim c(k-1)
	Dim s	
	For i = 0 To k-1
		If objTextReader.AtEndOfStream Then
			Exit For
		End If
		s = objTextReader.ReadLine()
		c(i) = Eval(s)
	Next
	
	'вычисление константы логарифмирования
	Dim l				
		l= Round(32767/(1+log(c(0)/c(n-1)/min)/log(32767)),0)	
	
	' Запись процесса логарифмирования
	Set objTextWriter = objFSO.OpenTextFile("HDR_calibration.pgm", 2, True)
	For i = 1 To k
		objTextWriter.WriteLine("load w" & i)
		objTextWriter.WriteLine("add put")
		objTextWriter.WriteLine("log " & l)
		objTextWriter.WriteLine("save e" & i)
	Next	
	
	' Приведение логарфимированных изображений к единому уровню яркости
	For i = 1 To k
		objTextWriter.WriteLine("load e" & i)
		objTextWriter.WriteLine("offset " & Round(l * log(c(0)/c(i-1)/min)/log(32767) ,0) )
		objTextWriter.WriteLine("clipmin 0 0")
		objTextWriter.WriteLine("save g" & i)
	Next
	
	objTextWriter.Close()
	Set objTextWriter = Nothing
	' Уничтожение объекта и закрытие первого файла
	
	' Выбор, складывать ли полученные изображения или нет
	If MsgBox ("Хотите ли вы выполнить сложение полученных файлов?", vbYesNo, "Сложение") = vbNo Then
		WScript.Quit
	Else
		Const x	= 8192		'начало границы смешивания
		Dim cheat
		cheat=InputBox("Насколько ослабить вклад коротких экспозиций?"& vbCrLf & vbCrLf & vbCrLf & "0 — адаптивное сложение исходя только из экспозиций" & vbCrLf & vbCrLf & "1 — оптимальное значение, подходящее для большинства ситуаций" & vbCrLf & vbCrLf & "20 — нет адаптивного сложения, все сигналы ниже границы смешивания отбрасываются" , "Параметры сложения", "1")
		ReDim cheat_array(k-1)	'создание массива для ослабления вклада коротких экспозиций
		ReDim bound_array(k-1)	'создание массива пересчитаных границ смешения кадров		
		ReDim I_max_array(k-1)	'создание массива максимальных значений в соответствующем кадре		
		For i = 0 To k-1
			cheat_array(i)=Round((log(c(0)/c(i))/log(2)+0.95)^(log(c(0)/c(i))/log(2)/(2.4/(cheat+1.0E-19))) ,2)
			bound_array(i)= l * log(x*c(0)/c(i)/min)/log(32767)
			I_max_array(i)= l * log(32767*c(0)/c(i)/min)/log(32767)
		Next
				
		' Открываем для записи второй файл
		Set objTextWriter = objFSO.OpenTextFile("HDR_addition.pgm", 2, True)
		objTextWriter.WriteLine("load g1")
		objTextWriter.WriteLine("save z1")
		For i = 1 To k-1
			objTextWriter.WriteLine("load z1")
			objTextWriter.WriteLine("offset "& -Round( bound_array(i-1) ,0 ) )	
			objTextWriter.WriteLine("clipmin 0 0")					'обрезание нижней границы для формирования затухания
			objTextWriter.WriteLine("save n1")						'следующий шаг завершит формирование параболического затухания сигнала нижнего кадра
			objTextWriter.WriteLine("prod n1 " & 1/(2*( bound_array(i-1) - I_max_array(i-1)  ))  )
			objTextWriter.WriteLine("add z1")						'нижний кадр сформирован. следующий шаг умножит на весовой коэффициент для оптимального сложения
			objTextWriter.WriteLine("mult " & Round(  c(0)/c(i)*cheat_array(i)/(c(0)/c(i)*cheat_array(i)+1),5)  )
			objTextWriter.WriteLine("save z1")						'нижний кадр готов к сумированию с верхним кадром
			objTextWriter.WriteLine("load g" & i+1)					'загрузка нижнего кадра
			objTextWriter.WriteLine("offset "& -Round( bound_array(i-1) ,0 ) )
			objTextWriter.WriteLine("clipmin 0 0")					'обрезание нижней границы нижнего кадра
			objTextWriter.WriteLine("save n1")						'формирование параболического нарастания сигнала
			objTextWriter.WriteLine("prod n1 " & 1/(2*( I_max_array(i-1) - bound_array(i-1)  )))
			objTextWriter.WriteLine("clipmax " & Round(( I_max_array(i-1) - bound_array(i-1) )/2,0) & " " & Round(( I_max_array(i-1) - bound_array(i-1) )/2,0))
			objTextWriter.WriteLine("save n1")						'предыдущий шаг выполнил обрезку той части, которая должна остаться линейной и мы сохранили параболический кусок
			objTextWriter.WriteLine("load g" & i+1)					
			objTextWriter.WriteLine("offset " & -Round( I_max_array(i-1) ,0))
			objTextWriter.WriteLine("clipmin 0 0")					'обрезание сигнала по границе нижнего кадра, где получилось переполнение
			objTextWriter.WriteLine("add n1")						'добавление нарастающего параболического куска от верхнего кадра
			objTextWriter.WriteLine("mult " & Round( c(0)/c(i)*cheat_array(i)/(c(0)/c(i)*cheat_array(i)+1),5) )
			objTextWriter.WriteLine("save n1")						'умножили на весовой коэффициент как для нижнего изображения, чтобы потом для нарастающей части его сложить со второй половиной
			objTextWriter.WriteLine("load g" & i+1)					'загрузили верхнее изображение
			objTextWriter.WriteLine("mult " & Round(1/(c(0)/c(i)*cheat_array(i)+1),5) )		'умножили его на второй весовой коэффициент
			objTextWriter.WriteLine("add n1")						'и добавили к итогу. Теперь нижний линейный кусок сложится с весом, а оставшаяся часть ляжет сверху, как недостающая часть пирамиды
			objTextWriter.WriteLine("add z1")
			objTextWriter.WriteLine("save z1")
		Next
	' Закрываем файл
		objTextWriter.Close()
		' Уничтожение объекта и закрытие второго файла
	End if
	
	Set objTextWriter = Nothing
	Set objFSO = Nothing