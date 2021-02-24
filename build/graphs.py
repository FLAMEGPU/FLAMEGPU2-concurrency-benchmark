import matplotlib.pyplot as plt
import numpy as np
import csv


initialPopSize = 0 
finalPopSize = 0
popSizeIncrement = 0

initialNumSpecies = 0
finalNumSpecies = 0
numSpeciesIncrement = 0

with open('params.csv') as f:
  csvreader = csv.reader(f)

  popRow = next(csvreader)
  popRow = list(map(int, popRow))
  initialPopSize = popRow[0]
  finalPopSize = popRow[1]
  popSizeIncrement = popRow[2]

  speciesRow = next(csvreader)
  speciesRow = list(map(int, speciesRow))
  initialNumSpecies = speciesRow[0]
  finalNumSpecies = speciesRow[1]
  numSpeciesIncrement = speciesRow[2]     

with open('results.csv') as f:
  csvreader = csv.reader(f) 
  fig, ax = plt.subplots()
  for row in csvreader:
    row = list(map(float, row))
    ax.plot(np.arange(initialNumSpecies, finalNumSpecies + 1, numSpeciesIncrement),row,"^--", linewidth=1)
  ax.grid(True)
  ax.set_title('Average step time against number of species')
  ax.set_ylabel('Average Step time (ms)')
  ax.set_xlabel('Number of species')
  ax.xaxis.set_ticks(np.arange(initialNumSpecies, finalNumSpecies + 1, numSpeciesIncrement))
  ax.legend(np.arange(initialPopSize, finalPopSize + 1, popSizeIncrement), title="Population Size")
  plt.show()
