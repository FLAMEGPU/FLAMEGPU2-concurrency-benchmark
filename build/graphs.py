import matplotlib.pyplot as plt
import numpy as np
import csv
import os


initialPopSize = 0 
finalPopSize = 0
popSizeIncrement = 0

initialNumSpecies = 0
finalNumSpecies = 0
numSpeciesIncrement = 0

for subdir, dirs, files in os.walk('results/'):
  print(subdir)
  if (subdir != "results/"):
    if (files != []):
      with open(subdir + '/params.csv') as f:
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
      
      with open(subdir + '/serial.csv') as serial:
        with open(subdir + '/concurrent.csv') as concurrent:
          fig, ax = plt.subplots()
          
          # Read in data
          serialRows = []
          concurrentRows = []
          
          csvreader = csv.reader(serial)
          for row in csvreader:
            row = list(map(float, row))
            serialRows.append(row)
            
          csvreader = csv.reader(concurrent)
          for row in csvreader:
            row = list(map(float, row))
            concurrentRows.append(row)
            
          # Plot serial results
          for row in serialRows:
            ax.plot(np.arange(initialNumSpecies, finalNumSpecies + 1, numSpeciesIncrement),row,"^--", linewidth=1)
            
          # Plot concurrent results
          for row in concurrentRows:
            ax.plot(np.arange(initialNumSpecies, finalNumSpecies + 1, numSpeciesIncrement),row,"^-", linewidth=1)
          
          # Display timing results  
          ax.grid(True)
          ax.set_title('Average step time against number of species')
          ax.set_ylabel('Average Step time (ms)')
          ax.set_xlabel('Number of species')
          ax.xaxis.set_ticks(np.arange(initialNumSpecies, finalNumSpecies + 1, numSpeciesIncrement))
          legendNums = np.arange(initialPopSize, finalPopSize + 1, popSizeIncrement)
          legend = list(map(str, legendNums))
          legend2 = list(map(lambda a : str(a) + " (concurrent)", legendNums))
          legend = np.concatenate((legend, legend2))
          ax.legend(legend, title="Population Size")
    
          plt.savefig(subdir + '/timing.png')
    
            
          # Plot speedup
          fig2, ax2 = plt.subplots()
          for s, c in zip(serialRows, concurrentRows):
            r = []
            for i in range(len(s)):
              r.append(s[i] / c[i])
            ax2.plot(np.arange(initialNumSpecies, finalNumSpecies + 1, numSpeciesIncrement), r, "^-", linewidth=1)
      
          ax2.set_title('Speedup against number of species')
          ax2.set_ylabel('Speedup')
          ax2.set_xlabel('Number of species')
          ax2.set_ylim([1.0, None])
          ax2.xaxis.set_ticks(np.arange(initialNumSpecies, finalNumSpecies + 1, numSpeciesIncrement))
          ax2.legend(np.arange(initialPopSize, finalPopSize + 1, popSizeIncrement), title="Population Size")
          plt.savefig(subdir + '/speedup.png')
          #plt.show()
    
