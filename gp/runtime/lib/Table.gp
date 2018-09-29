defineClass Table columnNames rows changeCount

method columnNames Table { return columnNames }
method columnCount Table { return (count columnNames) }
method rowCount Table { return (count rows) }
method count Table { return (count rows) }
method isEmpty Table { return ((count rows) == 0) }
method changeCount Table { return changeCount }
method rows Table { return rows }

to table columnNames... {
  colNames = (list)
  for i (argCount) {
	cName = (arg i)
	if (isNil cName) { cName = (join 'C' i) }
    add colNames (toString cName)
  }
  return (new 'Table' (toArray colNames) (list) 0)
}

method addRow Table data {
  // Add the given row (a list or array) to this table.
  // If newRow is not as wide as the table, pad it with empty cells.
  // If it is wider, discard any extra cells.

  colCount = (count columnNames)
  if (colCount < 1) { return }
  if (isAnyClass data 'Array' 'List') {
	newRow = (newArray colCount '')
	for i (min colCount (count data)) {
	  atPut newRow i (at data i)
	}
  } else {
	newRow = (newArray colCount '')
	atPut newRow 1 data
  }
  add rows newRow
  changeCount += 1
}

method add Table rowData... {
  colCount = (columnCount this)
  i = 2
  newRow = (newArray colCount)
  for c colCount {
    atPut newRow c (arg i)
    i += 1
  }
  add rows newRow
  changeCount += 1
}

method addAll Table aList {
  colCount = (columnCount this)
  newRowCount = (ceiling ((count aList) / colCount))
  addCount = (count aList)
  i = 1
  repeat newRowCount {
    newRow = (newArray colCount)
	for c colCount {
	  if (i < addCount) { atPut newRow c (at aList i) }
	  i += 1
	}
	add rows newRow
  }
  changeCount += 1
}

method cellAt Table row col {
  r = (at rows row)
  if (isClass r 'Array') {
	return (at r (columnIndex this col))
  } else {
	if (isClass col 'Integer') {
	  if (and (1 <= col) (col <= (count columnNames))) {
		col = (at columnNames col)
	  }
	}
	if (hasField r col) {
	  return (getField r col)
	} else {
	  return nil
	}
  }
}

method cellAtPut Table row col value {
  r = (at rows row)
  if (isClass r 'Array') {
	atPut r (columnIndex this col) value
  } else {
	if (isClass col 'Integer') {
	  if (and (1 <= col) (col <= (count columnNames))) {
		col = (at columnNames col)
	  }
	}
	if (hasField r col) { setField r col value }
  }
  changeCount += 1
}

method row Table row {
  return (at rows row)
}

method rowAtPut Table rowIndex newRow {
  atPut rows rowIndex newRow
  changeCount += 1
}

method insertRow Table rowIndex newRow {
  addAt rows rowIndex newRow
  changeCount += 1
}

method removeRow Table rowIndex {
  removeAt rows rowIndex
  changeCount += 1
}

method column Table col {
  cIndex = (columnIndex this col)
  result = (list)
  for i (count rows) {
	v = (cellAt this i cIndex)
	if (notNil v) { add result v }
  }
  return result
}

method renameColumn Table col newName {
  cIndex = (columnIndex this col)
  if (notNil cIndex) {
	atPut columnNames cIndex newName
  }
  changeCount += 1
}

method removeColumn Table col {
  cIndex = (columnIndex this col)
  if (isNil cIndex) { return }
  columnNames = (join (copyFromTo columnNames 1 (cIndex - 1)) (copyFromTo columnNames (cIndex + 1)))
  newRows = (list)
  for r rows {
	if (isClass r 'Array') {
	  add newRows (join (copyFromTo r 1 (cIndex - 1)) (copyFromTo r (cIndex + 1)))
	} else {
	  add newRows r
	}
  }
  rows = newRows
  changeCount += 1
}

method insertColumnAfter Table col newColName {
  if (or (isNil newColName) ('' == newColName)) { newColName = 'C' }
  newColName = (uniqueNameNotIn columnNames newColName)
  cIndex = (columnIndex this col)
  if (isNil cIndex) { cIndex = (columnCount this) }
  columnNames = (join (copyFromTo columnNames 1 cIndex) (array newColName) (copyFromTo columnNames (cIndex + 1)))
  newRows = (list)
  for r rows {
	if (isClass r 'Array') {
	  add newRows (join (copyFromTo r 1 cIndex) (array '') (copyFromTo r (cIndex + 1)))
	} else {
	  add newRows r
	}
  }
  rows = newRows
  changeCount += 1
}

method summarizeColumn Table col {
  if ((count rows) == 0) { return 'no data' }
  cIndex = (columnIndex this col)
  firstRowValue = (cellAt this 1 cIndex)
  if (isNumber firstRowValue) {
	values = (sorted (column this col))
	result = (dictionary)
	atPut result 'min' (first values)
	atPut result 'max' (last values)
	atPut result 'median' (at values (half (count values)))
	atPut result 'mean' ((sum values) / (count values))
	return result
  } else {
	count = (count (uniqueValuesForColumn this col))
	return (join '' count ' unique values')
  }
}

method uniqueValuesForColumn Table col {
  // Return an array of unique values for the given column in their order of appearance.
  cIndex = (columnIndex this col)
  result = (list)
  unique = (dictionary)
  for r (count rows) {
    v = (cellAt this r cIndex)
    if (not (contains unique v)) {
	  add result v
	  add unique v
	}
  }
  return result
}

method filterInPlace Table col op value {
  filtered = (filtered this col op value)
  rows = (rows filtered)
  changeCount += 1
}

method filtered Table col op value {
  // Return a table containing rows for which the given column
  // satisfies the selection operation and value.

  if ((count rows) == 0) { return (new 'Table' columnNames  (array)) }

  if ('=' == op) { op = '==' } // allow '=' as a synonym for '=='

  cIndex = (columnIndex this col)
  firstRowValue = (cellAt this 1 cIndex)
  if ((classOf value) != (classOf firstRowValue)) {
	if (and (isClass value 'String') (isNumber firstRowValue)) { value = (toNumber value) }
	if (and (isClass firstRowValue 'String') (isNumber value)) { value = (toString value) }
  }

  matchingRows = (list)
  for r (count rows) {
    v = (cellAt this r cIndex)
    if (call op v value) { add matchingRows (at rows r) }
  }
  return (new 'Table' columnNames matchingRows)
}

method find Table col value startIndex {
  // Return the index of the first row for which the given column
  // has the given value or zero if no match is found.

  if (isNil startIndex) { startIndex = 1 }
  cIndex = (columnIndex this col)
  r = startIndex
  last = (count rows)
  while (r <= last) {
    if (value == (cellAt this r cIndex)) { return r }
	r += 1
  }
  return 0
}

method firstRowWhere Table col value... {
  // Return the  first row for which the given columns have the given values,
  // or nil if no match is found.
  // To do: Use an index dictionary to speed up repeated searches.

  cNames = (list)
  cIndices = (list)
  values = (list)
  i = 2
  while (i < (argCount)) {
	cIndex = (columnIndex this (arg i))
	if (isNil cIndex) { return nil }
	add cNames (arg i)
	add cIndices cIndex
	add values (arg (i + 1))
	i += 2
  }
  if (isEmpty cIndices) { return nil }
  cNames = (toArray cNames)
  cIndices = (toArray cIndices)
  values = (toArray values)
  cCount = (count cIndices)

  for row rows {
	match = true
 	j = 1
	while (and match (j <= cCount)) {
	  if (isClass row 'Array') {
		v = (at row (at cIndices j))
	  } else {
		cName = (at cNames j)
		if (hasField row cName) {
		  v = (getField row cName)
		} else {
		  v = nil
		  match = false
		}
	  }
	  if (v != (at values j)) { match = false }
	  j += 1
	}
	if match { return row }
  }
  return nil
}

method sortInPlace Table col op value {
  sorted = (sorted this col op value)
  rows = (rows sorted)
  changeCount += 1
}

method sorted Table col ascending {
  // Return a table containing rows of this table sorted by the
  // given column and sorting operation. If sortOp is not provided
  // it defaults to '<' (i.e. ascending order).

  sortOp = '<'
  if (ascending != true) { sortOp = '>' }
  if (isEmpty rows) { return (new 'Table' columnNames) }
  if (isClass (first rows) 'Array') {
	sortAction = (action
	  (function cIndex op r1 r2 { return (call op (at r1 cIndex) (at r2 cIndex)) })
	  (columnIndex this col)
	  sortOp
	)
	sorted = (sorted (toArray rows) sortAction)
  } else {
	// For now, assume the table contains only objects that have the field (column) used for sorting
	sortAction = (action
	  (function fName op r1 r2 { return (call op (getField r1 fName) (getField r2 fName)) })
	  col
	  sortOp
	)
	sorted = (sorted (toArray rows) sortAction)
  }
  return (new 'Table' columnNames (toList sorted))
}

method columnIndex Table col {
  if (isNumber col) { return (truncate col) }
  if (isClass col 'String') {
    index = (indexOf columnNames col)
	if (isNil index) {
	  error (join 'No column named ' col ' in table')
	}
	return index
  }
  return nil
}

method toString Table limit {
  if (isNil limit) { limit = 10 }
  tab = (string 9)
  cr = (newline)
  result = (list (join tab (joinStrings columnNames tab) cr))
  if ((count rows) == 0) {
	add result (join tab '(empty table)')
  } else {
	colCount = (count columnNames)
	for r (min (count rows) limit) {
	  add result (toString r)
	  add result tab
      for c colCount {
		add result (printString (cellAt this r c))
		if (c < colCount) { add result tab }
	  }
	  add result cr
	}
  }
  return (joinStrings (toArray result))
}

// Import/export

to importTableFromFile fileName hasColumnNames delimiter {
  data = (readFile fileName)
  if (and (isNil data) (not (endsWith fileName '.csv'))) {
  	data = (readFile (join fileName '.csv'))
  }
  if (isNil data) { error 'Could not read file ' fileName }
  return (importCSV (table) data hasColumnNames delimiter)
}

method importCSV Table s hasColumnNames delimiter {
  // Import string data in "comma separated value" (.csv) format, replacing any
  // current data in this table. If hasColumnNames is true (the default), the
  // first line of data provides column names. If hasColumnNames and/or delimiter
  // are not provided, attempt to guess them.

  if (isNil delimiter) {
  	delimiter = (guessDelimiter this  s)
	if (isNil delimiter) {
	  error 'Could not guess delimiter; data may not be CSV format'
	}
  }
  if (isNil hasColumnNames) {
	hasColumnNames = (guessHasColumnNames this s delimiter)
  }
  rowData = (list)
  for line (lines s) {
	gcIfNeeded
	if (',' == delimiter) {
	  row = (list)
	  item = (list)
	  inQuote = false
	  for ch (letters line) {
		if ('"' == ch) {
		  inQuote = (not inQuote)
		} else {
		  if (and (not inQuote) (delimiter == ch)) {
			add row (joinStrings item)
			item = (list)
		  } else {
			add item ch
		  }
		}
	  }
	  add row (joinStrings item)
	} else {
	  row = (splitWith line delimiter)
	}
	if ((count row) > 0) {
	  if ('' == (last row)) {
		// many CSV files contain empty final columns; remove them
		i = (count row)
		while (and (i > 0) ('' == (at row i))) { i += -1 }
		row = (copyFromTo row 1 i)
	  }
	  if ((count row) > 0) { add rowData (toArray row) }
	}
  }
  if (isEmpty rowData) { error 'no data in CSV file' }

  if hasColumnNames { columnNames = (removeFirst rowData) }
  rows = rowData
  ensureAllColumnsHaveNames this
  padRowsIfNeeded this
  autoConvertNumericColumns this
  gc
  return this
}

method guessDelimiter Table s {
  lines = (firstTenLinesFrom this s)
  if ((count lines > 5)) { lines = (copyFromTo lines 2) } // skip first ine
  for delimiter (array ',' '	' ':' '|' ' ') { // try: comma, tab, colon, pipe, space
	counts = (dictionary)
	for line lines {
	  n = 0
	  inQuotes = false
	  for ch (letters line) {
		if ('"' == ch) { inQuotes = (not inQuotes) }
		if (and (not inQuotes) (ch == delimiter)) { n += 1 }
	  }
	  add counts n
	}
	if (and ((count counts) == 1) ((first (keys counts)) > 0)) {
	  return delimiter
	}
  }
  return nil
}

method guessHasColumnNames Table s delimiter {
  // Assume that the first line of a table is the column names for the table if the
  // any column has a string in the first row and a numeric value in in the second.
  // If in doubt, consider the first line to be data.
  lines = (firstTenLinesFrom this s)
  if ((count lines) < 2) { return false }
  fields1 = (splitWith (at lines 1) delimiter)
  fields2 = (splitWith (at lines 2) delimiter)
  for i (count fields1) {
	cell1 = (at fields1 i)
	cell2 = (at fields2 i)
	if (and (not (isNumber (toNumber cell1 nil))) (isNumber (toNumber cell2 nil))) {
	  return true
	}
  }
  return false
}

method firstTenLinesFrom Table s {
  // Return a the first ten lines from the string s.
  // If s has fewer than ten lines, return as many lines as possible.
  byteCount = (byteCount s)
  i = 1
  lineCount = 0
  while (i < byteCount) {
	ch = (byteAt s i)
	if (or (ch == 10) (ch == 13)) {
	  lineCount += 1
	  if (lineCount == 10) { return (lines (substring s 1 (i - 1))) }
	  if (i < byteCount) {
		if (and (ch == 10) ((byteAt s (i + 1)) == 13)) { i += 1 } // CR-LF line ending
		if (and (ch == 13) ((byteAt s (i + 1)) == 10)) { i += 1 } // LF-CR line ending
	  }
	}
	i += 1
  }
  return (lines s) // fewer than 10 lines
}

method ensureAllColumnsHaveNames Table {
  // Ensure that columnNames is the size of the longest row and that every column has a name.

  columnCount = 0
  for r rows {
	cols = (count r)
	if (cols > columnCount) { columnCount = cols }
  }

  oldNames = columnNames
  columnNames = (newArray columnCount)
  for i columnCount {
    if (i <= (count oldNames)) {
	  atPut columnNames i (at oldNames i)
	} else {
	  atPut columnNames i (join 'C' i)
	}
  }
}

method padRowsIfNeeded Table {
  // Ensure every row has at least columnCount entries.

  columnCount = (count columnNames)
  for i (count rows) {
	row = (at rows i)
	if ((count row) < columnCount) {
	  while ((count row) < columnCount) { row = (copyWith row '') } // pad short rows with empty strings
	  atPut rows i row
	}
  }
}

method autoConvertNumericColumns Table {
  if (isEmpty this) { return }

  columnCount = (count columnNames)
  newColumnData = (newArray columnCount)
  for i columnCount {
	atPut newColumnData i (list)
  }

  for r rows {
	for i columnCount {
	  done = true // set to false if we're still converting at least one column
	  if (notNil (at newColumnData i)) {
		v = (at r i)
		if (notNil v) { v = (toNumber v nil) }
		if (isNil v) {
		  atPut newColumnData i nil // stop converting column i
		} else {
		  add (at newColumnData i) v
		  done = false
		}
	  }
	}
	if done { return } // early out if no column is all numbers
  }

  for r rows {
	for i columnCount {
	  if (notNil (at newColumnData i)) {
		atPut r i (removeFirst (at newColumnData i))
	  }
	}
  }
}

method exportCSVToFile Table fileName delimiter {
  if (or (isNil fileName) (fileName == '')) {
	fileName = (uniqueNameNotIn (listFiles) 'tableData' 'csv')
  }
  if (not (endsWith fileName '.csv')) { fileName = (join fileName '.csv') }
  data = (exportCSV this delimiter)
  writeFile fileName data
}

method exportCSV Table delimiter {
  // Return a string representing this table in "comma separated value" (.csv) format,
  // using the given delimiter. The first line will be the column names.

  if (isNil delimiter) { delimiter = ',' }
  colCount = (count columnNames)
  lines = (list)
  add lines (joinStrings columnNames delimiter)
  rowStrings = (newArray colCount)
  for r (count rows) {
	for c colCount {
	  atPut rowStrings c (toString (cellAt this r c))
	}
	add lines (joinStrings rowStrings delimiter)
  }
  return (joinStrings lines (newline))
}
